# frozen_string_literal: true

require "project_types/script/test_helper"

describe Script::Layers::Infrastructure::ScriptProjectRepository do
  include TestHelpers::FakeFS

  let(:ctx) { TestHelpers::FakeContext.new }
  let(:instance) do
    Script::Layers::Infrastructure::ScriptProjectRepository.new(
    ctx: ctx,
    directory: directory,
    initial_directory: ctx.root
  )
  end

  let(:deprecated_ep_types) { [] }
  let(:supported_languages) { ["assemblyscript"] }
  let(:script_config_filename) { "script.config.yml" }

  let(:initial_directory) { ctx.root }
  let(:directory) { "/script_directory" }

  before do
    Script::Layers::Application::ExtensionPoints.stubs(:deprecated_types).returns(deprecated_ep_types)
    Script::Layers::Application::ExtensionPoints.stubs(:languages).returns(supported_languages)
  end

  describe "#create" do
    let(:script_name) { "script_name" }
    let(:extension_point_type) { "tax_filter" }
    let(:language) { "assemblyscript" }

    before do
      dir = "/#{script_name}"
      ctx.mkdir_p(dir)
      ctx.chdir(dir)
    end

    subject do
      ShopifyCLI::DB.stubs(:get).with(:acting_as_shopify_organization).returns(nil)

      instance.create(
        script_name: script_name,
        extension_point_type: extension_point_type,
        language: language
      )
    end

    describe "failure" do
      describe "when extension point is deprecated" do
        let(:deprecated_ep_types) { [extension_point_type] }

        it "should raise DeprecatedEPError" do
          assert_raises(Script::Layers::Infrastructure::Errors::DeprecatedEPError) { subject }
        end
      end

      describe "when language is not supported" do
        let(:supported_languages) { ["rust"] }

        it "should raise InvalidLanguageError" do
          assert_raises(Script::Layers::Infrastructure::Errors::InvalidLanguageError) { subject }
        end
      end
    end

    describe "success" do
      def it_should_create_a_new_script_project
        capture_io { subject }

        assert_nil subject.env
        assert_nil subject.uuid
        assert_equal script_name, subject.script_name
        assert_equal extension_point_type, subject.extension_point_type
        assert_equal language, subject.language
      end
    end
  end

  describe "#get" do
    subject { instance.get }

    let(:script_name) { "script_name" }
    let(:extension_point_type) { "tax_filter" }
    let(:language) { "assemblyscript" }
    let(:uuid) { "uuid" }
    let(:script_config) { "script.config.yml" }
    let(:script_config_content) do
      {
        "version" => "2",
        "title" => script_name,
        "configuration" => {
          "type": "single",
          "schema": [
            {
              "key": "configurationKey",
              "name": "My configuration field",
              "type": "single_line_text_field",
              "helpText": "This is some help text",
              "defaultValue": "This is a default value",
            },
          ],
        },
      }
    end
    let(:valid_config) do
      {
        "extension_point_type" => "tax_filter",
        "script_name" => "script_name",
        "script_config" => script_config,
      }
    end
    let(:actual_config) { valid_config }
    let(:current_project) do
      TestHelpers::FakeProject.new(directory: File.join(ctx.root, script_name), config: actual_config)
    end

    before do
      ShopifyCLI::Project.stubs(:has_current?).returns(true)
      ShopifyCLI::Project.stubs(:current).returns(current_project)
      ctx.write(script_config, script_config_content.to_json)
    end

    describe "when project config is valid" do
      describe "when env is empty" do
        it "should have empty env values" do
          assert_nil subject.env
          assert_nil subject.uuid
          assert_nil subject.api_key
        end
      end

      describe "when env has values" do
        let(:uuid) { "uuid" }
        let(:api_key) { "api_key" }
        let(:env) { ShopifyCLI::Resources::EnvFile.new(api_key: api_key, secret: "foo", extra: { "UUID" => uuid }) }

        it "should provide access to the env values" do
          ShopifyCLI::Project.any_instance.expects(:env).returns(env).at_least_once

          assert_equal env, subject.env
          assert_equal uuid, subject.uuid
          assert_equal api_key, subject.api_key
        end
      end

      it "should return the ScriptProject" do
        assert_equal current_project.directory, subject.id
        assert_equal script_name, subject.script_name
        assert_equal extension_point_type, subject.extension_point_type
        assert_equal language, subject.language
        assert_equal script_config_content["version"], subject.script_config.version
        assert_equal script_config_content["version"], subject.script_config.version
        assert_equal script_config_content["configuration"].to_json, subject.script_config.configuration.to_json
      end
    end

    describe "when extension point is deprecated" do
      let(:deprecated_ep_types) { [extension_point_type] }

      it "should raise DeprecatedEPError" do
        assert_raises(Script::Layers::Infrastructure::Errors::DeprecatedEPError) { subject }
      end
    end

    describe "when language is not supported" do
      let(:supported_languages) { ["rust"] }

      it "should raise InvalidLanguageError" do
        assert_raises(Script::Layers::Infrastructure::Errors::InvalidLanguageError) { subject }
      end
    end

    describe "when project is missing metadata" do
      def hash_except(config, *keys)
        config.slice(*(config.keys - keys))
      end

      describe "when missing extension_point_type" do
        let(:actual_config) { hash_except(valid_config, "extension_point_type") }

        it "should raise InvalidContextError" do
          assert_raises(Script::Layers::Infrastructure::Errors::InvalidContextError) { subject }
        end
      end

      describe "when missing script_name" do
        let(:actual_config) { hash_except(valid_config, "script_name") }

        it "should raise InvalidContextError" do
          assert_raises(Script::Layers::Infrastructure::Errors::InvalidContextError) { subject }
        end
      end

      describe "when missing script_config" do
        let(:actual_config) { hash_except(valid_config, "script_config") }

        it "should succeed" do
          assert subject
        end
      end

      describe "when missing uuid" do
        let(:actual_config) { hash_except(valid_config, "uuid") }

        it "should succeed" do
          assert subject
          assert_nil subject.uuid
        end
      end
    end
  end

  describe "#update_env" do
    subject { instance.update_env(**args) }

    let(:script_name) { "script_name" }
    let(:extension_point_type) { "tax_filter" }
    let(:language) { "assemblyscript" }
    let(:uuid) { "uuid" }
    let(:updated_uuid) { "updated_uuid" }
    let(:script_config) { "script.config.yml" }
    let(:script_config_content) { { "version" => "2", "title" => script_name }.to_json }
    let(:env) { ShopifyCLI::Resources::EnvFile.new(api_key: "123", secret: "foo", extra: env_extra) }
    let(:env_extra) { { "uuid" => "original_uuid", "something" => "else" } }
    let(:valid_config) do
      {
        "project_type" => "script",
        "organization_id" => 1,
        "uuid" => uuid,
        "extension_point_type" => "tax_filter",
        "script_name" => "script_name",
        "script_config" => script_config,
      }
    end
    let(:args) do
      {
        uuid: updated_uuid,
      }
    end

    before do
      dir = "/#{script_name}"
      ctx.mkdir_p(dir)
      ctx.chdir(dir)

      ShopifyCLI::DB.stubs(:get).with(:acting_as_shopify_organization).returns(nil)
      instance.create(
        script_name: script_name,
        extension_point_type: extension_point_type,
        language: language
      )
      ctx.write(script_config, script_config_content)
      ShopifyCLI::Project.any_instance.expects(:env).returns(env).at_least_once
    end

    describe "when updating an immutable property" do
      let(:args) do
        {
          extension_point_type: "a",
          language: "b",
          script_name: "c",
          project_type: "d",
          organization_id: "e",
        }
      end

      it "should do nothing" do
        previous_config = ShopifyCLI::Project.current.config
        assert subject
        updated_config = ShopifyCLI::Project.current.config
        assert_equal previous_config, updated_config
      end
    end

    describe "when updating uuid" do
      def hash_except(config, *keys)
        config.slice(*(config.keys - keys))
      end

      it "should update the property" do
        previous_env = ShopifyCLI::Project.current.env.to_h
        assert subject
        ShopifyCLI::Project.clear
        updated_env = ShopifyCLI::Project.current.env.to_h

        assert_equal hash_except(previous_env, "UUID"), hash_except(updated_env, "UUID")
        refute_equal previous_env["UUID"], updated_env["UUID"]
        assert_equal updated_uuid, updated_env["UUID"]
        assert_equal updated_uuid, subject.uuid
      end
    end
  end

  describe "#update_script_config" do
    let(:new_title) { "new title" }
    let(:new_configuration_ui) { true }
    let(:current_project) do
      TestHelpers::FakeProject.new(directory: ctx.root, config: project_config)
    end
    let(:project_config) do
      {
        "project_type" => "script",
        "organization_id" => 1,
        "uuid" => "uuid",
        "extension_point_type" => "tax_filter",
        "script_name" => "script_name",
      }
    end

    before do
      ShopifyCLI::Project.stubs(:has_current?).returns(true)
      ShopifyCLI::Project.stubs(:current).returns(current_project)
    end

    subject { instance.update_script_config(title: new_title) }

    describe "script.config.yml does not exist" do
      it "raises NoScriptConfigYmlFileError" do
        assert_raises(Script::Layers::Infrastructure::Errors::NoScriptConfigYmlFileError) { subject }
      end
    end

    describe "script.config.yml already exists" do
      let(:initial_title) { "my scripts title" }
      let(:initial_description) { "my description" }
      let(:script_config_content) do
        {
          "version" => "2",
          "title" => initial_title,
          "description" => initial_description,
          "configuration" => {
            "type": "single",
            "schema": [
              {
                "key": "configurationKey",
                "name": "My configuration field",
                "type": "single_line_text_field",
                "helpText": "This is some help text",
                "defaultValue": "This is a default value",
              },
            ],
          },
        }
      end

      before do
        ctx.write(script_config_filename, script_config_content.to_yaml)
      end

      it "updates only the provided fields" do
        script_config = subject.script_config
        file_content = YAML.load(ctx.read(script_config_filename))

        assert_equal new_title, script_config.title
        assert_equal new_title, file_content["title"]
        refute_equal initial_title, script_config.title

        assert_equal initial_description, script_config.content["description"]
        assert_equal initial_description, file_content["description"]
        assert_equal script_config_content["version"], script_config.version
        assert_equal script_config_content["version"], file_content["version"]
        assert_equal script_config_content["configuration"].to_json, script_config.configuration.to_json
        assert_equal script_config_content["configuration"].to_json, file_content["configuration"].to_json
      end
    end

    describe "script.json already exists" do
      let(:initial_title) { "my scripts title" }
      let(:initial_description) { "my description" }
      let(:script_config_content) do
        {
          "version" => "2",
          "title" => initial_title,
          "description" => initial_description,
          "configuration" => {
            "type": "single",
            "schema": [
              {
                "key": "configurationKey",
                "name": "My configuration field",
                "type": "single_line_text_field",
                "helpText": "This is some help text",
                "defaultValue": "This is a default value",
              },
            ],
          },
        }
      end
      let(:script_config_filename) { "script.json" }

      before do
        ctx.write(script_config_filename, script_config_content.to_json)
      end

      it "updates only the provided fields" do
        script_config = subject.script_config
        file_content = JSON.parse(ctx.read(script_config_filename))

        assert_equal new_title, script_config.title
        assert_equal new_title, file_content["title"]
        refute_equal initial_title, script_config.title

        assert_equal initial_description, script_config.content["description"]
        assert_equal initial_description, file_content["description"]
        assert_equal script_config_content["version"], script_config.version
        assert_equal script_config_content["version"], file_content["version"]
        assert_equal script_config_content["configuration"].to_json, script_config.configuration.to_json
        assert_equal script_config_content["configuration"].to_json, file_content["configuration"].to_json
      end
    end
  end

  describe "ScriptConfigYmlRepository" do
    let(:instance) { Script::Layers::Infrastructure::ScriptProjectRepository::ScriptConfigYmlRepository.new(ctx: ctx) }
    let(:version) { "2" }
    let(:title) { "title" }
    let(:content) { { "version" => version, "title" => title }.to_yaml }

    describe "active?" do
      subject { instance.active? }

      describe "when file does not exist" do
        it "returns false" do
          refute subject
        end
      end

      describe "when file exists" do
        before do
          File.write(script_config_filename, content)
        end

        it "returns true" do
          assert subject
        end
      end
    end

    describe "get!" do
      subject { instance.get! }

      describe "when file does not exist" do
        it "raises NoScriptConfigFileError" do
          assert_raises(Script::Layers::Infrastructure::Errors::NoScriptConfigFileError) { subject }
        end
      end

      describe "when file exists" do
        before do
          File.write(script_config_filename, content)
        end

        describe "when content is invalid yaml" do
          let(:content) { "*" }

          it "raises InvalidScriptConfigYmlDefinitionError" do
            assert_raises(Script::Layers::Infrastructure::Errors::InvalidScriptConfigYmlDefinitionError) { subject }
          end
        end

        describe "when content is not a hash" do
          let(:content) { "" }

          it "raises InvalidScriptConfigYmlDefinitionError" do
            assert_raises(Script::Layers::Infrastructure::Errors::InvalidScriptConfigYmlDefinitionError) { subject }
          end
        end

        describe "when content is missing fields" do
          let(:content) { {}.to_yaml }

          it "raises MissingScriptConfigYmlFieldError" do
            assert_raises(Script::Layers::Infrastructure::Errors::MissingScriptConfigYmlFieldError) { subject }
          end
        end

        describe "when content is valid yaml" do
          it "returns the entity" do
            assert_equal version, subject.version
            assert_equal title, subject.title
            assert_nil subject.description
            assert subject.configuration_ui
            assert_nil subject.configuration
          end
        end
      end
    end

    describe "update!" do
      let(:new_title) { "new title" }
      subject { instance.update!(title: new_title) }

      describe "when file does not exist" do
        it "raises NoScriptConfigFileError" do
          assert_raises(Script::Layers::Infrastructure::Errors::NoScriptConfigFileError) { subject }
        end
      end

      describe "when file does exist" do
        before do
          File.write(script_config_filename, content)
        end

        it "updates the ScriptConfig" do
          assert_equal version, subject.version
          assert_equal new_title, subject.title
          assert_nil subject.description
          assert subject.configuration_ui
          assert_nil subject.configuration
        end

        it "updates the file" do
          subject
          file_content = YAML.load(File.read(script_config_filename))
          assert_equal version, file_content["version"]
          assert_equal new_title, file_content["title"]
        end
      end
    end
  end

  describe "#create_project_directory" do
    subject do
      instance.create_project_directory
    end

    describe "when another folder with this name already exists" do
      let(:existing_file) { File.join(directory, "existing-file.txt") }
      let(:existing_file_content) { "Some content." }

      before do
        ctx.mkdir_p(directory)
        ctx.write(existing_file, existing_file_content)
      end

      it "should not delete the original project during cleanup and raise ScriptProjectAlreadyExistsError" do
        assert_raises(Script::Layers::Infrastructure::Errors::ScriptProjectAlreadyExistsError) { subject }
        assert ctx.dir_exist?(directory)
        assert_equal existing_file_content, File.read(existing_file)
      end
    end

    describe "success" do
      it "should create a new project directory and change_directory into it" do
        subject
        assert_equal directory, ctx.root
        ctx.dir_exist?(directory)
      end
    end
  end

  describe "#delete_project_directory" do
    before do
      ctx.mkdir_p(directory)
      ctx.chdir(directory)
    end

    subject do
      instance.delete_project_directory
    end

    it "should delete the directory, and change to the initial directory" do
      subject
      assert_equal initial_directory, ctx.root
      refute ctx.dir_exist?(directory)
    end
  end

  describe "#change_to_initial_directory" do
    subject do
      instance.change_to_initial_directory
    end

    before do
      ctx.mkdir_p(directory)
    end

    it "should change to the initial directory" do
      subject
      assert_equal ctx.root, initial_directory
    end
  end

  describe "ScriptJsonRepository" do
    let(:instance) { Script::Layers::Infrastructure::ScriptProjectRepository::ScriptJsonRepository.new(ctx: ctx) }
    let(:version) { "2" }
    let(:title) { "title" }
    let(:content) { { "version" => version, "title" => title }.to_json }
    let(:script_config_filename) { "script.json" }

    describe "active?" do
      subject { instance.active? }

      describe "when file does not exist" do
        it "returns false" do
          refute subject
        end
      end

      describe "when file exists" do
        before do
          File.write(script_config_filename, content)
        end

        it "returns true" do
          assert subject
        end
      end
    end

    describe "get!" do
      subject { instance.get! }

      describe "when file does not exist" do
        it "raises NoScriptConfigFileError" do
          assert_raises(Script::Layers::Infrastructure::Errors::NoScriptConfigFileError) { subject }
        end
      end

      describe "when file exists" do
        before do
          File.write(script_config_filename, content)
        end

        describe "when content is invalid json" do
          let(:content) { "{[}]" }

          it "raises InvalidScriptJsonDefinitionError" do
            assert_raises(Script::Layers::Infrastructure::Errors::InvalidScriptJsonDefinitionError) { subject }
          end
        end

        describe "when content is not a hash" do
          let(:content) { "" }

          it "raises InvalidScriptJsonDefinitionError" do
            assert_raises(Script::Layers::Infrastructure::Errors::InvalidScriptJsonDefinitionError) { subject }
          end
        end

        describe "when content is missing fields" do
          let(:content) { {}.to_json }

          it "raises MissingScriptJsonFieldError" do
            assert_raises(Script::Layers::Infrastructure::Errors::MissingScriptJsonFieldError) { subject }
          end
        end

        describe "when content is valid yaml" do
          it "returns the entity" do
            assert_equal version, subject.version
            assert_equal title, subject.title
            assert_nil subject.description
            assert subject.configuration_ui
            assert_nil subject.configuration
          end
        end
      end
    end

    describe "update!" do
      let(:new_title) { "new title" }
      subject { instance.update!(title: new_title) }

      describe "when file does not exist" do
        it "raises NoScriptConfigFileError" do
          assert_raises(Script::Layers::Infrastructure::Errors::NoScriptConfigFileError) { subject }
        end
      end

      describe "when file does exist" do
        before do
          File.write(script_config_filename, content)
        end

        it "updates the ScriptConfig" do
          assert_equal version, subject.version
          assert_equal new_title, subject.title
          assert_nil subject.description
          assert subject.configuration_ui
          assert_nil subject.configuration
        end

        it "updates the file" do
          subject
          file_content = JSON.parse(File.read(script_config_filename))
          assert_equal version, file_content["version"]
          assert_equal new_title, file_content["title"]
        end
      end
    end
  end
end
