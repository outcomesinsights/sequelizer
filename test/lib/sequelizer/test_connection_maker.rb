require_relative '../../test_helper'
require 'sequelizer'

class TestConnectionMaker < Minitest::Test

  def setup
    @options = { 'adapter' => 'mock', 'host' => 'postgres' }
  end

  def test_accepts_options_as_params
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      assert_equal :postgres, Sequelizer::ConnectionMaker.new(@options).connection.database_type
    end
  end

  def with_ignored_yaml_config(opts = {}); end

  def with_yaml_config(options = {}, &block)
    yaml_config = Sequelizer::YamlConfig.new
    yaml_config.stub(:options, options) do
      Sequelizer::YamlConfig.stub :new, yaml_config, &block
    end
  end

  def with_env_config(options = {})
    env_config = Sequelizer::EnvConfig.new
    env_config.stub(:options, options) do
      Sequelizer::EnvConfig.stub :new, env_config do
        yield env_config
      end
    end
  end

  def test_reads_options_from_yaml_config
    with_yaml_config(@options) do
      assert_equal :postgres, Sequelizer::ConnectionMaker.new.connection.database_type
    end
  end

  def test_ignores_options_from_yaml_config_when_asked
    with_yaml_config(@options) do
      assert_nil Sequelizer::ConnectionMaker.new(ignore_yaml: true).options.to_hash[:adapter]
    end
  end

  def test_applies_settings_if_given
    with_yaml_config(@options.merge(postgres_db_opt_flim: :flam)) do
      with_env_config do
        conn = Sequelizer::ConnectionMaker.new.connection
        conn.test_connection

        assert_equal(['SET flim=flam'], conn.sqls)
      end
    end
  end

  def test_applies_settings_for_all_connections_if_given
    with_yaml_config(@options.merge(postgres_db_opt_flim: :flam, max_connections: 2, preconnect: :concurrent)) do
      with_env_config do
        conn = Sequelizer::ConnectionMaker.new.connection
        conn.test_connection

        assert_equal(['SET flim=flam'] * 2, conn.sqls)
      end
    end
  end

  def test_reads_options_from_env_config_if_no_yaml_config
    with_yaml_config do
      with_env_config(@options) do
        assert_equal :postgres, Sequelizer::ConnectionMaker.new.connection.database_type
      end
    end
  end

  def test_ignores_options_from_env_config_if_no_yaml_config
    with_yaml_config do
      with_env_config(@options) do
        assert_nil Sequelizer::ConnectionMaker.new(ignore_env: true).options.to_hash[:adapter]
      end
    end
  end

  def test_applies_configuration_to_connection
    opts = @options.merge(postgres_db_opt_search_path: 'searchy', impala_db_opt_search_path: 'searchy2')
    with_yaml_config(opts) do
      conn = Sequelizer::ConnectionMaker.new.connection
      conn.test_connection

      assert_equal({ search_path: 'searchy' }, conn.db_opts.to_hash)
      assert_equal(['SET search_path=searchy'], conn.db_opts.sql_statements)
    end
  end

  def test_applies_nothing_when_no_configuration
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      conn = Sequelizer::ConnectionMaker.new(@options).connection
      conn.test_connection

      assert_empty(conn.db_opts.to_hash)
      assert_empty(conn.db_opts.sql_statements)
    end
  end

  def test_applies_quotes_when_necessary
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      @options.merge!(postgres_db_opt_search_path: 'searchy,path')
      conn = Sequelizer::ConnectionMaker.new(@options).connection
      conn.test_connection

      assert_equal({ search_path: "'searchy,path'" }, conn.db_opts.to_hash)
      assert_equal(["SET search_path='searchy,path'"], conn.db_opts.sql_statements)
    end
  end

  def test_applies_extensions
    with_yaml_config(@options.merge(extension_error_sql: 1)) do
      assert_includes Sequelizer::ConnectionMaker.new.connection.send(:instance_variable_get, :@loaded_extensions), :error_sql,
                      "Extension wasn't set"
    end
  end

  def test_jdbc_hive2_adapter_configuration
    options = {
      'adapter' => 'jdbc_hive2',
      'host' => 'hive-server',
      'database' => 'test_db',
      'port' => 10_000
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new

      # Test the configuration without actually connecting
      test_opts = options.dup
      maker.send(:configure_adapter_specific_options, test_opts)

      # Should create JDBC connection with proper URI
      expected_uri = "jdbc:hive2://hive-server:10000/test_db;auth=noSasl"
      assert_equal expected_uri, test_opts[:uri]
      assert_equal :jdbc, test_opts[:adapter]
    end
  end

  def test_jdbc_hive2_with_kerberos_authentication
    options = {
      'adapter' => 'jdbc_hive2',
      'host' => 'hive-server',
      'database' => 'test_db',
      'realm' => 'EXAMPLE.COM',
      'principal' => 'hive',
      'host_fqdn' => 'hive-server.example.com'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new

      test_opts = options.dup
      maker.send(:configure_adapter_specific_options, test_opts)

      expected_uri = "jdbc:hive2://hive-server:21050/test_db;principal=hive%2Fhive-server.example.com%40EXAMPLE.COM"
      assert_equal expected_uri, test_opts[:uri]
    end
  end

  def test_jdbc_hive2_with_user_password_authentication
    options = {
      'adapter' => 'jdbc_hive2',
      'host' => 'hive-server',
      'database' => 'test_db',
      'user' => 'testuser',
      'password' => 'testpass'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new

      test_opts = options.dup
      maker.send(:configure_adapter_specific_options, test_opts)

      expected_uri = "jdbc:hive2://hive-server:21050/test_db;user=testuser;password=testpass"
      assert_equal expected_uri, test_opts[:uri]
    end
  end

  def test_jdbc_impala_adapter_configuration
    options = {
      'adapter' => 'jdbc_impala',
      'host' => 'impala-server',
      'database' => 'test_db',
      'port' => 21_051
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new

      test_opts = options.dup
      maker.send(:configure_adapter_specific_options, test_opts)

      expected_uri = "jdbc:impala://impala-server:21051/test_db"
      assert_equal expected_uri, test_opts[:uri]
      assert_equal :jdbc, test_opts[:adapter]
    end
  end

  def test_jdbc_impala_with_kerberos_authentication
    options = {
      'adapter' => 'jdbc_impala',
      'host' => 'impala-server',
      'database' => 'test_db',
      'realm' => 'EXAMPLE.COM',
      'principal' => 'impala',
      'host_fqdn' => 'impala-server.example.com'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new

      test_opts = options.dup
      maker.send(:configure_adapter_specific_options, test_opts)

      expected_uri = "jdbc:impala://impala-server:21050/test_db;AuthMech=1;KrbServiceName=impala;KrbAuthType=2;KrbHostFQDN=impala-server.example.com;KrbRealm=EXAMPLE.COM"
      assert_equal expected_uri, test_opts[:uri]
    end
  end

  def test_jdbc_impala_with_user_password_authentication
    options = {
      'adapter' => 'jdbc_impala',
      'host' => 'impala-server',
      'database' => 'test_db',
      'user' => 'testuser',
      'password' => 'testpass'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      expected_uri = "jdbc:impala://impala-server:21050/test_db;AuthMech=3;UID=testuser;PWD=testpass"
      assert_equal expected_uri, conn.opts[:uri]
    end
  end

  def test_jdbc_impala_with_user_only_authentication
    options = {
      'adapter' => 'jdbc_impala',
      'host' => 'impala-server',
      'database' => 'test_db',
      'user' => 'testuser'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      expected_uri = "jdbc:impala://impala-server:21050/test_db;AuthMech=2;UID=testuser"
      assert_equal expected_uri, conn.opts[:uri]
    end
  end

  def test_jdbc_postgres_adapter_configuration
    options = {
      'adapter' => 'jdbc_postgres',
      'host' => 'postgres-server',
      'database' => 'test_db',
      'port' => 5433
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      expected_uri = "jdbc:postgresql://postgres-server:5433/test_db"
      assert_equal expected_uri, conn.opts[:uri]
      assert_equal :jdbc, conn.opts[:adapter]
    end
  end

  def test_jdbc_postgres_with_authentication
    options = {
      'adapter' => 'jdbc_postgres',
      'host' => 'postgres-server',
      'database' => 'test_db',
      'user' => 'testuser',
      'password' => 'testpass'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      expected_uri = "jdbc:postgresql://postgres-server:5432/test_db?user=testuser&password=testpass"
      assert_equal expected_uri, conn.opts[:uri]
    end
  end

  def test_jdbc_postgres_with_user_only
    options = {
      'adapter' => 'jdbc_postgres',
      'host' => 'postgres-server',
      'database' => 'test_db',
      'user' => 'testuser'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      expected_uri = "jdbc:postgresql://postgres-server:5432/test_db?user=testuser"
      assert_equal expected_uri, conn.opts[:uri]
    end
  end

  def test_impala_adapter_configuration
    options = {
      'adapter' => 'impala',
      'host' => 'impala-server',
      'database' => 'test_db',
      'port' => 21_001
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      assert_equal 'impala', conn.opts[:adapter]
      assert_equal 'test_db', conn.opts[:database]
      assert_equal 21_001, conn.opts[:port]
    end
  end

  def test_impala_adapter_defaults
    options = {
      'adapter' => 'impala',
      'host' => 'impala-server'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      assert_equal 'default', conn.opts[:database]
      assert_equal 21_000, conn.opts[:port]
    end
  end

  def test_impala_with_kerberos_sasl
    options = {
      'adapter' => 'impala',
      'host' => 'impala-server',
      'principal' => 'impala',
      'host_fqdn' => 'impala-server.example.com'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      assert_equal :sasl, conn.opts[:transport]
      assert_equal 'GSSAPI', conn.opts[:sasl_params][:mechanism]
      assert_equal 'impala-server.example.com', conn.opts[:sasl_params][:remote_host]
      assert_equal 'impala', conn.opts[:sasl_params][:remote_principal]
    end
  end

  def test_connection_with_uri_parameter
    options = {
      'uri' => 'postgres://user:pass@host:5432/database'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      # When URI is provided, it should be used directly
      assert_equal 'postgres://user:pass@host:5432/database', conn.opts[:uri]
    end
  end

  def test_connection_with_url_parameter
    options = {
      'url' => 'mysql://user:pass@host:3306/database'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      # When URL is provided, it should be used directly
      assert_equal 'mysql://user:pass@host:3306/database', conn.opts[:uri]
    end
  end

  def test_url_escaping_in_connection_strings
    options = {
      'adapter' => 'jdbc_hive2',
      'host' => 'server-with-dash',
      'database' => 'test@db',
      'user' => 'user@domain.com',
      'password' => 'pass word!'
    }

    with_yaml_config(options) do
      maker = Sequelizer::ConnectionMaker.new
      conn = maker.connection

      # Check that special characters are URL encoded
      assert_includes conn.opts[:uri], 'test%40db'
      assert_includes conn.opts[:uri], 'user%40domain.com'
      assert_includes conn.opts[:uri], 'pass%20word%21'
    end
  end

end
