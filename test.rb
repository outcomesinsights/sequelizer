require 'sequelizer'
include Sequelizer

#d = db(url: 'postgresql://ryan:r@localhost/test_data_for_jigsaw?search_path=omopv4_plus_250')
#p d[:person].limit(1).all

d = db(url: 'impala://ryan:r@localhost/test_data_for_jigsaw?search_path=omopv4_plus_250')
p d[:person].limit(1).all
