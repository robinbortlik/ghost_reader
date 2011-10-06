require 'logger'
require 'ostruct'
require 'i18n/backend/base'
require 'i18n/backend/memoize'
require 'ghost_reader/new_client'

module GhostReader
  class NewBackend
    module Implementation

      attr_accessor :config, :missings

      # for options see code of default_config
      def initialize(conf={})
        self.config = OpenStruct.new(default_config.merge(conf))
        yield(config) if block_given?
        config.logger = Logger.new(config.logfile || STDOUT)
        config.client = NewClient.new(config.service)
      end

      def start_agents
        spawn_retriever
        spawn_reporter
        self
      end

      protected

      # this won't be called if memoize kicks in
      def lookup(locale, key, scope = [], options = {})
        raise 'no fallback given' if config.fallback.nil?
        config.fallback.translate(locale, key, options).tap do |result|
          raise 'result is a hash' if result.is_a?(Hash) # TODO
          track({ key => { locale => { 'default' => result } } })
        end
      end

      def track(missings)
        return if self.missings.nil? # not yet initialized
        self.missings.deep_merge!(missings)
      end

      # performs initial and incremental requests
      def spawn_retriever
        Thread.new do
          @memoized_lookup = config.client.initial_request[:data]
          self.missings = {} # initialized
          until false
            sleep config.retrieval_interval
            config.logger.debug "Incremental request."
            response = config.client.incremental_request
            if response[:status] == 200
              flattend = flatten_translations_in_all_locales(response[:data])
              @memoized_lookup.deep_merge! flattend
            end
          end
        end
      end

      # performs reporting requests
      def spawn_reporter
        Thread.new do
          until false
            sleep config.report_interval
            unless self.missings.empty?
              config.logger.debug "Reporting request with #{self.missings.keys.size} missings."
              config.client.reporting_request(missings)
              missings.clear
            else
              config.logger.debug "Reporting request omitted, nothing to report."
            end
          end
        end
      end

      def flatten_translations_in_all_locales(data)
        data.inject({}) do |result, key_value|
          key, value = key_value
          result.merge key => flatten_translations(key, value, true, false)
        end
      end

      def default_config
        {
          :retrieval_interval => 15,
          :report_interval => 10,
          :fallback => nil, # a I18n::Backend (mandatory)
          :logfile => nil, # a path
          :service => nil # nested hash, see GhostReader::NewClient#default_config
        }
      end
    end

    include I18n::Backend::Base
    include Implementation
    include I18n::Backend::Memoize # provides @memoized_lookup
    include I18n::Backend::Flatten # provides #flatten_translations
  end
end
