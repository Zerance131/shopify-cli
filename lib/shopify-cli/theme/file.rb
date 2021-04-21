# frozen_string_literal: true
require_relative "mime_type"

module ShopifyCli
  module Theme
    class File < Struct.new(:path)
      attr_reader :relative_path
      attr_accessor :remote_checksum

      def initialize(path, root)
        super(Pathname.new(path))

        # Path may be relative or absolute depending on the source.
        # By converting both the path and the root to absolute paths, we
        # can safely fetch a relative path.
        @relative_path = self.path.expand_path.relative_path_from(root.expand_path)
      end

      def read
        path.read
      end

      def exist?
        path.exist?
      end

      def mime_type
        @mime_type ||= MimeType.by_filename(relative_path)
      end

      def text?
        mime_type.text?
      end

      def liquid?
        path.extname == ".liquid"
      end

      def json?
        path.extname == ".json"
      end

      def template?
        relative_path.to_s.start_with?("templates/")
      end

      def checksum
        content = read
        if mime_type.json?
          # Normalize JSON to match backend
          begin
            content = JSON.generate(JSON.parse(content))
          rescue JSON::JSONError
            # Fallback to using the raw content
          end
        end
        Digest::MD5.hexdigest(content)
      end

      # Make it possible to check whether a given File is within a list of Files with `include?`,
      # some of which may be relative paths while others are absolute paths.
      def ==(other)
        relative_path == other.relative_path
      end
    end
  end
end
