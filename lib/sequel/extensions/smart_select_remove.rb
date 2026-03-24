# frozen_string_literal: true

#
# The smart_select_remove extension overrides select_remove to resolve
# column information from the dataset's expression tree before falling
# back to the original select_remove behavior (which executes SQL via
# columns!).
#
# This is essential for lazy query building patterns where datasets
# reference tables that may not exist yet at query-build time. By
# walking through from_self chains and inspecting inner SELECT lists,
# this extension can determine which columns to keep without touching
# the database.
#
# You should load this extension into all of a database's datasets:
#
#   DB.extension(:smart_select_remove)
#
# This automatically loads the select_remove extension as well.
#
# Related module: Sequel::SmartSelectRemove

module Sequel

  module SmartSelectRemove

    # Override select_remove to attempt static column resolution before
    # falling back to the original implementation.
    #
    # When the dataset has no explicit SELECT clause, walks through
    # from_self chains to find inner column expressions and resolves
    # them to outer-scope symbol names. This avoids the columns! call
    # that the original select_remove uses, which would execute SQL.
    #
    # @param cols [Array<Symbol>] columns to remove
    # @return [Sequel::Dataset] dataset with columns removed
    def select_remove(*cols)
      # If there's an explicit select, original behavior handles it
      return super if @opts[:select] && !@opts[:select].empty?

      # Try to resolve columns by walking the from_self chain
      if (inner_cols = resolve_selected_columns)
        outer_cols = inner_cols.map { |c| resolve_outer_column_name(c) }
        # All columns must be resolvable; bail to super if any are opaque
        return super if outer_cols.any?(&:nil?)

        return select(*(outer_cols - cols))
      end

      super
    end

    private

    # Walk through from_self chains to find the innermost explicit
    # SELECT list. Returns nil if no explicit selection is found.
    #
    # @param ds [Sequel::Dataset] the dataset to inspect
    # @return [Array, nil] the inner SELECT expressions, or nil
    def resolve_selected_columns(ds = self)
      opts = ds.opts
      if (sel = opts[:select]) && !sel.empty?
        sel
      elsif (from = opts[:from]&.first)
        case from
        when Sequel::Dataset
          resolve_selected_columns(from)
        when Sequel::SQL::AliasedExpression
          resolve_selected_columns(from.expression) if from.expression.is_a?(Sequel::Dataset)
        end
      end
    end

    # Map an inner SELECT expression to its outer-scope column name.
    # After from_self, inner expressions become subquery output columns
    # referenced by their alias or base name in the outer scope.
    #
    # @param col [Object] a column expression from the inner SELECT
    # @return [Symbol, nil] the outer column name, or nil if unresolvable
    def resolve_outer_column_name(col)
      case col
      when Symbol
        col
      when Sequel::SQL::AliasedExpression
        a = col.alias
        a.is_a?(Symbol) ? a : a.to_sym
      when Sequel::SQL::QualifiedIdentifier
        resolve_outer_column_name(col.column)
      when Sequel::SQL::Identifier
        col.value.to_sym
      end
    end

  end

  Database.register_extension(:smart_select_remove) do |db|
    db.extension(:select_remove)
    db.extend_datasets(SmartSelectRemove)
  end

end
