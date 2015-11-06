require "azure"
require 'fastlane/erb_template_helper'

class ::File
  def each_chunk(chunk_size=2**22)
    yield read(chunk_size) until eof?
  end
end

module Fastlane
  module Actions
    module SharedValues
      AZURE_IPA_OUTPUT_PATH = :AZURE_IPA_OUTPUT_PATH
      AZURE_DSYM_OUTPUT_PATH = :AZURE_DSYM_OUTPUT_PATH
      AZURE_PLIST_OUTPUT_PATH = :AZURE_PLIST_OUTPUT_PATH
    end

    class AzureAction < Action
      def self.description
        "Uploads to Azure Blob Storage"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :ipa,
                                       env_name: "",
                                       description: ".ipa file for the build",
                                       optional: true,
                                       default_value: Actions.lane_context[SharedValues::IPA_OUTPUT_PATH]),
          FastlaneCore::ConfigItem.new(key: :dsym,
                                       env_name: "",
                                       description: "zipped .dsym package for the build",
                                       optional: true,
                                       default_value: Actions.lane_context[SharedValues::DSYM_OUTPUT_PATH]),
          FastlaneCore::ConfigItem.new(key: :plist_template,
                                       env_name: "",
                                       description: "plist template file for the build",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :account_name,
                                       env_name: "AZURE_ACCOUNT_NAME",
                                       description: "Azure Account Name",
                                       optional: true,
                                       default_value: ENV['AZURE_ACCOUNT_NAME']),
           FastlaneCore::ConfigItem.new(key: :access_key,
                                        env_name: "AZURE_ACCESS_KEY",
                                        description: "Azure Access Key",
                                        optional: true,
                                        default_value: ENV['AZURE_ACCESS_KEY']),
           FastlaneCore::ConfigItem.new(key: :container,
                                        env_name: "AZURE_CONTAINER",
                                        description: "Azure Container",
                                        optional: true,
                                        default_value: ENV['AZURE_CONTAINER']),
           FastlaneCore::ConfigItem.new(key: :path,
                                        env_name: "",
                                        description: "Azure path to store uploads",
                                        optional: true),
           FastlaneCore::ConfigItem.new(key: :bundle_id,
                                        env_name: "",
                                        description: "App id for releases",
                                        optional: true),
           FastlaneCore::ConfigItem.new(key: :bundle_version,
                                        env_name: "",
                                        description: "App version for releases",
                                        optional: true),
           FastlaneCore::ConfigItem.new(key: :title,
                                        env_name: "",
                                        description: "App title for releases",
                                        optional: true),
        ]

      end

      def self.is_supported?(platform)
        platform == :ios
      end

      def self.run(config)
        params = {}
        params[:ipa] = config[:ipa]
        params[:dsym] = config[:dsym]
        params[:plist_template] = config[:plist_template]
        params[:bundle_id] = config[:bundle_id]
        params[:bundle_version] = config[:bundle_version]
        params[:title] = config[:title]
        params[:account_name] = config[:account_name]
        params[:access_key] = config[:access_key]
        params[:container] = config[:container]
        params[:path] = config[:path]

        raise "No Azure account name given, pass using `account_name: 'account name'`".red unless params[:account_name].to_s.length > 0
        raise "No Azure access key given, pass using `access_key: 'access key'`".red unless params[:access_key].to_s.length > 0
        raise "No Azure container given, pass using `container: 'container'`".red unless params[:container].to_s.length > 0
        raise "No IPA file path given, pass using `ipa: 'ipa path'`".red unless params[:ipa].to_s.length > 0
        raise "No path given, pass using `path: 'path'`".red unless params[:path].to_s.length > 0

        # Pass in or read from the ipa? Going with pass in for now
        if params[:plist_template].to_s.length > 0
          raise "plist template requires bundle id, pass using `bundle_id: 'bundle_id'`".red unless params[:bundle_id].to_s.length > 0
          raise "plist template requires bundle version, pass using `bundle_version: 'bundle_version'`".red unless params[:bundle_version].to_s.length > 0
          raise "plist template requires title, pass using `title: 'title'`".red unless params[:title].to_s.length > 0
        end

        eth = Fastlane::ErbTemplateHelper

        # Had to use global Azure variables rather than creating a local client
        Azure.storage_account_name = params[:account_name]
        Azure.storage_access_key = params[:access_key]

        ipa_file_name = File.basename(params[:ipa])
        ipa_azure_path = File.join(params[:path], ipa_file_name)
        ipa_azure_url = "https://#{params[:account_name]}.blob.core.windows.net/#{ipa_azure_path}"
        upload_file(Azure.blobs, params[:container], ipa_azure_path, params[:ipa])

        if params[:dsym].to_s.length > 0
          dsym_file_name = File.basename(params[:dsym])
          dsym_azure_path = File.join(params[:path], dsym_file_name)
          dsym_azure_url = "https://#{params[:account_name]}.blob.core.windows.net/#{dsym_azure_path}"
          upload_file(Azure.blobs, params[:container], dsym_azure_path, params[:dsym])
        end

        if params[:plist_template].to_s.length > 0 && File.exist?(params[:plist_template])
          plist_file_name = File.basename(ipa_file_name, '.*') + ".plist"
          plist_azure_path = File.join(params[:path], plist_file_name)
          plist_azure_url = "https://#{params[:account_name]}.blob.core.windows.net/#{plist_azure_url}"

          plist_template = eth.load_from_path(params[:plist_template])
          plist_render = eth.render(plist_template, {
            url: ipa_azure_url,
            bundle_id: params[:bundle_id],
            bundle_version: params[:bundle_version],
            title: params[:title]
          })

          Helper.log.info "Uploading plist to #{params[:container]}/#{plist_azure_path}"
          Azure.blobs.create_block_blob(params[:container], plist_azure_path, plist_render)
        end

        Actions.lane_context[SharedValues::AZURE_IPA_OUTPUT_PATH] = ipa_azure_url
        ENV[SharedValues::AZURE_IPA_OUTPUT_PATH.to_s] = ipa_azure_url

        if dsym_azure_url.to_s.length > 0
          Actions.lane_context[SharedValues::AZURE_DSYM_OUTPUT_PATH] = dsym_azure_url
          ENV[SharedValues::AZURE_DSYM_OUTPUT_PATH.to_s] = dsym_azure_url
        end

        if plist_azure_url.to_s.length > 0
          Actions.lane_context[SharedValues::AZURE_PLIST_OUTPUT_PATH] = plist_azure_url
          ENV[SharedValues::AZURE_PLIST_OUTPUT_PATH.to_s] = plist_azure_url
        end
      end

      def self.upload_file(service, container, blob, filepath)
        Helper.log.info "Uploading #{filepath} to #{container}/#{blob}"

        block_list = []
        counter = 0
        open(filepath, 'rb') do |f|
          f.each_chunk {|chunk|
            block_id = counter.to_s.rjust(5, '0')
            block_list << [block_id, :uncommitted]
            service.create_blob_block(container, blob, block_id, chunk)
            Helper.log.info "Uploaded chunk #{counter}"
            counter += 1
          }
        end

        # https://github.com/Azure/azure-sdk-for-ruby/issues/294
        service.client.reset_agents!
        service.commit_blob_blocks(container, blob, block_list)
        Helper.log.info "Done uploading #{filepath} to #{container}/#{blob}"
      end
    end
  end
end
