# frozen_string_literal: true
module Script
  class Command
    class Connect < ShopifyCLI::Command::SubCommand
      prerequisite_task :ensure_authenticated
      prerequisite_task ensure_project_type: :script

      def call(_args, _)
        Layers::Application::ConnectApp.call(ctx: @ctx, force: true, strict: true)
      rescue StandardError => e
        UI::ErrorHandler.pretty_print_and_raise(e, failed_op: @ctx.message("script.connect.error.operation_failed"))
      end

      def self.help
        ShopifyCLI::Context.new.message("connect.help", ShopifyCLI::TOOL_NAME, ShopifyCLI::TOOL_NAME)
      end
    end
  end
end
