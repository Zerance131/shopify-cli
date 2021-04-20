# frozen_string_literal: true
require "thread"
require "json"
require "base64"

module ShopifyCli
  module Theme
    class Uploader
      class Operation < Struct.new(:method, :file)
        def to_s
          "#{method} #{file&.relative_path}"
        end
      end
      API_VERSION = "unstable"

      attr_reader :checksums

      def initialize(ctx, theme)
        @ctx = ctx
        @theme = theme

        # Queue of `Operation`s waiting to be picked up from a thread for processing.
        @queue = Queue.new
        # `Operation`s will be removed from this Array completed.
        @pending = []
        # Thread making the API requests.
        @threads = []
        # Mutex used to pause all threads when backing-off when hitting API rate limits
        @backoff_mutex = Mutex.new

        # Allows delaying log of errors, mainly to not break the progress bar.
        @delay_errors = false
        @delayed_errors = []

        # Latest theme assets checksums. Updated on each upload.
        @checksums = {}
      end

      def enqueue_updates(files)
        files.each { |file| enqueue(:update, file) }
      end

      def enqueue_deletes(files)
        files.each { |file| enqueue(:delete, file) }
      end

      def size
        @pending.size
      end

      def empty?
        @pending.empty?
      end

      def pending_updates
        @pending.select { |op| op.method == :update }.map(&:file)
      end

      def remote_file?(file)
        checksums.key?(@theme[file].relative_path.to_s)
      end

      def wait!
        raise ThreadError, "No uploader threads" if @threads.empty?
        total = size
        last_size = size
        until empty? || @queue.closed?
          if block_given? && last_size != size
            yield size, total
            last_size = size
          end
          Thread.pass
        end
      end

      def fetch_checksums!
        _status, response = ShopifyCli::AdminAPI.rest_request(
          @ctx,
          shop: @theme.shop,
          path: "themes/#{@theme.id}/assets.json",
          api_version: API_VERSION,
        )
        update_checksums(response)
      end

      def shutdown
        @queue.close unless @queue.closed?
      ensure
        @threads.each { |thread| thread.join if thread.alive? }
      end

      def start_threads(count = 2)
        count.times do
          @threads << Thread.new do
            loop do
              operation = @queue.pop
              break if operation.nil? # shutdown was called
              perform(operation)
            rescue => e
              report_error(
                "{{red:ERROR}} {{blue:#{operation}}}: #{e}" +
                (@ctx.debug? ? "\n\t#{e.backtrace.join("\n\t")}" : "")
              )
            end
          end
        end
      end

      def delay_errors!
        @delay_errors = true
      end

      def report_errors!
        @delay_errors = false
        @delayed_errors.each { |error| report_error(error) }
        @delayed_errors.clear
      end

      def upload_theme!(&block)
        fetch_checksums!

        removed_files = checksums.keys - @theme.theme_files.map { |file| file.relative_path.to_s }

        enqueue_updates(@theme.liquid_files)
        enqueue_updates(@theme.json_files)

        # Wait for liquid & JSON files to upload, because those are rendered remotely
        wait!(&block)

        # Process lower-priority files in the background

        # Assets are served locally, so can be uploaded in the background
        enqueue_updates(@theme.asset_files)

        # Delete removed files
        enqueue_deletes(removed_files)
      end

      private

      def enqueue(method, file)
        operation = Operation.new(method, @theme[file])

        # Already enqueued
        return if @pending.include?(operation)

        if @theme.ignore?(operation.file)
          @ctx.debug("ignore #{operation.file.relative_path}")
          return
        end

        unless method == :delete || file_has_changed?(operation.file)
          @ctx.debug("skip #{operation}")
          return
        end

        @pending << operation
        @queue << operation unless @queue.closed?
      end

      def perform(operation)
        return if @queue.closed?
        wait_for_backoff!
        @ctx.debug(operation.to_s)

        response = send(operation.method, operation.file)

        # Check if the API told us we're near the rate limit
        if !backingoff? && (limit = response["x-shopify-shop-api-call-limit"])
          used, total = limit.split("/").map(&:to_i)
          backoff_if_near_limit!(used, total)
        end
      rescue ShopifyCli::API::APIRequestError => e
        report_error(
          "{{red:ERROR}} {{blue:#{operation}}}:\n\t" +
          parse_api_error(e).join("\n\t")
        )
      ensure
        @pending.delete(operation)
      end

      def update(file)
        asset = { key: file.relative_path.to_s }
        if file.text?
          asset[:value] = file.read
        else
          asset[:attachment] = Base64.encode64(file.read)
        end

        _status, body, response = ShopifyCli::AdminAPI.rest_request(
          @ctx,
          shop: @theme.shop,
          path: "themes/#{@theme.id}/assets.json",
          method: "PUT",
          api_version: API_VERSION,
          body: JSON.generate(asset: asset)
        )

        update_checksums(body)

        response
      end

      def delete(file)
        _status, _body, response = ShopifyCli::AdminAPI.rest_request(
          @ctx,
          shop: @theme.shop,
          path: "themes/#{@theme.id}/assets.json",
          method: "DELETE",
          api_version: API_VERSION,
          body: JSON.generate(asset: {
            key: file.relative_path.to_s
          })
        )

        response
      end

      def update_checksums(api_response)
        api_response.values.flatten.each do |asset|
          @checksums[asset["key"]] = asset["checksum"]
        end
      end

      def file_has_changed?(file)
        file.checksum != @checksums[file.relative_path.to_s]
      end

      def report_error(error)
        if @delay_errors
          @delayed_errors << error
        else
          @ctx.puts(error)
        end
      end

      def parse_api_error(exception)
        messages = JSON.parse(exception&.response&.body).dig("errors", "asset")
        return [exception.message] unless messages
        # Truncate to first lines
        messages.map! { |message| message.split("\n", 2).first }
      rescue JSON::ParserError
        exception.message
      end

      def backoff_if_near_limit!(used, limit)
        if used > limit - @threads.size
          @ctx.debug("Near API call limit, waiting 2 sec ...")
          @backoff_mutex.synchronize { sleep 2 }
        end
      end

      def backingoff?
        @backoff_mutex.locked?
      end

      def wait_for_backoff!
        # Sleeping in the mutex in another thread. Wait for unlock
        @backoff_mutex.synchronize {} if backingoff?
      end
    end
  end
end
