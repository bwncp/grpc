# Copyright 2015 gRPC authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'etc'
require 'mkmf'

windows = RUBY_PLATFORM =~ /mingw|mswin/
bsd = RUBY_PLATFORM =~ /bsd/
darwin = RUBY_PLATFORM =~ /darwin/
linux = RUBY_PLATFORM =~ /linux/
cross_compiling = ENV['RCD_HOST_RUBY_VERSION'] # set by rake-compiler-dock in build containers

grpc_root = File.expand_path(File.join(File.dirname(__FILE__), '../../../..'))

grpc_config = ENV['GRPC_CONFIG'] || 'opt'

ENV['MACOSX_DEPLOYMENT_TARGET'] = '10.10'

if ENV['AR'].nil? || ENV['AR'].size == 0
    ENV['AR'] = RbConfig::CONFIG['AR']
end
if ENV['CC'].nil? || ENV['CC'].size == 0
    ENV['CC'] = RbConfig::CONFIG['CC']
end
if ENV['CXX'].nil? || ENV['CXX'].size == 0
    ENV['CXX'] = RbConfig::CONFIG['CXX']
end
if ENV['LD'].nil? || ENV['LD'].size == 0
    ENV['LD'] = ENV['CC']
end

if darwin && !cross_compiling
  ENV['AR'] = 'libtool'
  ENV['ARFLAGS'] = '-o'
end

ENV['EMBED_OPENSSL'] = 'true'
ENV['EMBED_ZLIB'] = 'true'
ENV['EMBED_CARES'] = 'true'

ENV['ARCH_FLAGS'] = RbConfig::CONFIG['ARCH_FLAG']
if darwin && !cross_compiling
  if RUBY_PLATFORM =~ /arm64/
    ENV['ARCH_FLAGS'] = '-arch arm64'
  else
    ENV['ARCH_FLAGS'] = '-arch i386 -arch x86_64'
  end
end

ENV['CPPFLAGS'] = '-DGPR_BACKWARDS_COMPATIBILITY_MODE'
ENV['CPPFLAGS'] += ' -DGRPC_XDS_USER_AGENT_NAME_SUFFIX="\"RUBY\"" '
ENV['CPPFLAGS'] += ' -DGRPC_XDS_USER_AGENT_VERSION_SUFFIX="\"1.43.0.dev\"" '

output_dir = File.expand_path(RbConfig::CONFIG['topdir'])
grpc_lib_dir = File.join(output_dir, 'libs', grpc_config)
ENV['BUILDDIR'] = output_dir

unless windows
  puts 'Building internal gRPC into ' + grpc_lib_dir
  nproc = 4
  nproc = Etc.nprocessors * 2 if Etc.respond_to? :nprocessors
  make = bsd ? 'gmake' : 'make'
  system("#{make} -j#{nproc} -C #{grpc_root} #{grpc_lib_dir}/libgrpc.a CONFIG=#{grpc_config} Q=")
  exit 1 unless $? == 0
end

$CFLAGS << ' -I' + File.join(grpc_root, 'include')

ext_export_file = File.join(grpc_root, 'src', 'ruby', 'ext', 'grpc', 'ext-export')
$LDFLAGS << ' -Wl,--version-script="' + ext_export_file + '.gcc"' if linux
$LDFLAGS << ' -Wl,-exported_symbols_list,"' + ext_export_file + '.clang"' if darwin

$LDFLAGS << ' ' + File.join(grpc_lib_dir, 'libgrpc.a') unless windows
if grpc_config == 'gcov'
  $CFLAGS << ' -O0 -fprofile-arcs -ftest-coverage'
  $LDFLAGS << ' -fprofile-arcs -ftest-coverage -rdynamic'
end

if grpc_config == 'dbg'
  $CFLAGS << ' -O0 -ggdb3'
end

$LDFLAGS << ' -Wl,-wrap,memcpy' if linux
$LDFLAGS << ' -static-libgcc -static-libstdc++' if linux
$LDFLAGS << ' -static' if windows

$CFLAGS << ' -std=c99 '
$CFLAGS << ' -Wall '
$CFLAGS << ' -Wextra '
$CFLAGS << ' -pedantic '

output = File.join('grpc', 'grpc_c')
puts 'Generating Makefile for ' + output
create_makefile(output)

strip_tool = RbConfig::CONFIG['STRIP']
strip_tool += ' -x' if darwin

if grpc_config == 'opt'
  File.open('Makefile.new', 'w') do |o|
    o.puts 'hijack: all strip'
    o.puts
    File.foreach('Makefile') do |i|
      o.puts i
    end
    o.puts
    o.puts 'strip: $(DLLIB)'
    o.puts "\t$(ECHO) Stripping $(DLLIB)"
    o.puts "\t$(Q) #{strip_tool} $(DLLIB)"
  end
  File.rename('Makefile.new', 'Makefile')
end
