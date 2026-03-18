require 'uri'

module Sequelizer

  class MissingOptionalAdapterError < LoadError
  end

  module OptionalAdapterSupport

    OPTIONAL_ADAPTERS = {
      duckdb: {
        gems: %w[duckdb sequel-duckdb].freeze,
        libraries: %w[duckdb sequel-duckdb].freeze,
        bundle_group: 'duckdb',
      },
      hexspace: {
        gems: ['sequel-hexspace'].freeze,
        libraries: ['sequel-hexspace'].freeze,
        bundle_group: 'hexspace',
      },
    }.freeze

    class << self

      def require_adapter!(options)
        adapter = adapter_from_options(options)
        return unless adapter

        config = OPTIONAL_ADAPTERS.fetch(adapter)
        config[:libraries].each { |library| load_library(library) }
      rescue LoadError => e
        raise missing_optional_adapter_error(adapter, e) if adapter && optional_dependency_load_error?(adapter, e)

        raise
      end

      private

      def adapter_from_options(options)
        opts = options.transform_keys(&:to_sym)
        adapter = opts[:adapter] || scheme_from_url(opts[:uri] || opts[:url])
        return unless adapter

        adapter = adapter.to_s.downcase.to_sym
        OPTIONAL_ADAPTERS.key?(adapter) ? adapter : nil
      end

      def scheme_from_url(url)
        return unless url

        URI.parse(url.to_s).scheme
      end

      def load_library(library)
        require library
      end

      def optional_dependency_load_error?(adapter, error)
        config = OPTIONAL_ADAPTERS.fetch(adapter)
        path = error.path.to_s

        config[:libraries].any? do |library|
          path == library || path.end_with?("/#{library}")
        end
      end

      def missing_optional_adapter_error(adapter, error)
        config = OPTIONAL_ADAPTERS.fetch(adapter)
        gems = config[:gems].map { |name| "'#{name}'" }.join(', ')

        MissingOptionalAdapterError.new(
          "#{adapter} connections require optional gems #{gems}. " \
          "Add them to your bundle and install with BUNDLE_WITH=#{config[:bundle_group]} " \
          "(or declare the gems directly) before selecting the #{adapter} adapter.",
        ).tap do |wrapped_error|
          wrapped_error.set_backtrace(error.backtrace)
        end
      end

    end

  end

end
