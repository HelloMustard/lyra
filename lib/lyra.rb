require 'rainbow'
require 'lyra/client'
require 'lyra/client_config'
require 'lyra/config'
require 'lyra/item'
require 'lyra/logger'
require 'lyra/secret'
require 'lyra/template'
require 'lyra/version'
require 'terminal-table'
require 'thor'

module Lyra
  class Error < StandardError; end

  class CLI < Thor
    class_option :verbose, aliases: :v, type: :boolean, default: false

    desc 'exec --access_key_id <aws access key id> --secret_access_key <aws secret access key> --config <path to Lyrafile>', 'Pulls the secrets from your AWS Secrets Manager instance and builds a file from template'
    option :access_key_id, aliases: :b, type: :string
    option :secret_access_key, aliases: :s, type: :string
    option :aws_region, aliases: :r, type: :string
    option :environment, aliases: :e, type: :string
    option :config, aliases: :c, type: :string, default: "#{ENV['PWD']}/Lyrafile"
    option :working_directory, aliases: :d, type: :string, default: '.'
    def exec
      configure_logger(verbose: options[:verbose])

      raise Thor::Error, Rainbow("Cannot find Lyrafile at #{@options[:config]}").red unless File.exist?(@options[:config])

      @config = Lyra::Config.new(path: @options[:config])

      access_key_id = @options[:access_key_id] || ENV[@config.access_key_id]
      raise Thor::Error, Rainbow("access_key_id cannot be nil").red if access_key_id.nil?
      raise Thor::Error, Rainbow("access_key_id cannot be empty").red if access_key_id.empty?

      secret_access_key = @options[:secret_access_key] || ENV[@config.secret_access_key]
      raise Thor::Error, Rainbow("secret_access_key cannot be nil").red if secret_access_key.nil?
      raise Thor::Error, Rainbow("secret_access_key cannot be empty").red if secret_access_key.empty?

      aws_region = @options[:aws_region] || @config.aws_region
      raise Thor::Error, Rainbow("aws_region cannot be nil").red if aws_region.nil?
      raise Thor::Error, Rainbow("aws_region cannot be empty").red if aws_region.empty?

      environment = @options[:environment] || @config.environment

      client_config = Lyra::ClientConfig.new(access_key_id: access_key_id,
                                               secret_access_key: secret_access_key,
                                               aws_region: aws_region,
                                               environment: environment)
      @client = Lyra::Client.new(config: client_config)

      secret_list = []

      secrets = @config.secrets
      secrets.each do |s|
        secret = Lyra::Secret.new(hash: s)
        item_list = []

        remote_values = JSON.parse(@client.fetch_secret(secret_name: secret.name))
        secret.items.each do |i|
          item = Lyra::Item.new(hash: i)

          raise Thor::Error, Rainbow("Could not retrieve value for item #{item.name}").red if remote_values[item.key].nil?

          item.value = remote_values[item.key]
          item_list.append(item)
        end

        secret.items = item_list
        secret_list.append(secret)
      end

      template = Lyra::Template.new(secrets: secret_list, template_path: @config.template_path)
      template.generate(output_path: @config.output_path)
    end

    private

    def configure_logger(verbose: Boolean)
      log.level = verbose ? Logger::DEBUG : Logger::INFO
    end
  end

end
