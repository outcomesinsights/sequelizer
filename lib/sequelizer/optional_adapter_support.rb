require 'uri'

module Sequelizer

  class MissingOptionalAdapterError < LoadError
  end

  module OptionalAdapterSupport

    # Optional adapters are database drivers that live in separate gems
    # and are only needed when connecting to that specific database type.
    # Sequel handles adapter discovery and loading automatically via
    # `require "sequel/adapters/shared/#{scheme}"` (for mocks) and
    # `require "sequel/adapters/#{scheme}"` (for real connections).
    #
    # This module just detects when a connection targets an optional
    # adapter whose gems aren't installed and raises a helpful error.
    OPTIONAL_ADAPTERS = {
      duckdb: {
        gems: %w[duckdb sequel-duckdb].freeze,
        bundle_group: 'duckdb',
      },
      hexspace: {
        gems: ['sequel-hexspace'].freeze,
        bundle_group: 'hexspace',
      },
    }.freeze

    class << self

      # Called before Sequel.connect to provide a friendlier error
      # message when optional adapter gems are missing.
      def require_adapter!(options)
        adapter = adapter_from_options(options)
        return unless adapter

        # Let Sequel handle the actual loading — we just check that
        # the adapter gem is available in the bundle.
        config = OPTIONAL_ADAPTERS.fetch(adapter)
        config[:gems].each do |gem_name|
          Gem::Specification.find_by_name(gem_name)
        end
      rescue Gem::MissingSpecError
        raise missing_optional_adapter_error(adapter)
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

      def missing_optional_adapter_error(adapter)
        config = OPTIONAL_ADAPTERS.fetch(adapter)
        gems = config[:gems].map { |name| "'#{name}'" }.join(', ')

        MissingOptionalAdapterError.new(
          "#{adapter} connections require optional gems #{gems}. " \
          "Add them to your bundle and install with BUNDLE_WITH=#{config[:bundle_group]} " \
          "(or declare the gems directly) before selecting the #{adapter} adapter.",
        )
      end

    end

  end

end
