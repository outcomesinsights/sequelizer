require 'hashie'
module Sequelizer
  class OptionsHash < Hash

    include Hashie::Extensions::IndifferentAccess
    include Hashie::Extensions::MergeInitializer

  end
end
