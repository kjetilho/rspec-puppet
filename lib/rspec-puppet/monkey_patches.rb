require 'rubygems'

module Puppet
  # Allow rspec-puppet to prevent Puppet::Type from automatically picking
  # a provider for a resource. We need to do this because in order to fully
  # resolve the graph edges, we have to convert the Puppet::Resource objects
  # into Puppet::Type objects so that their autorequires are evaluated. We need
  # to prevent provider code from being called during this process as it's very
  # platform specific.
  class Type
    old_set_default = instance_method(:set_default)

    define_method(:set_default) do |attr|
      return if attr == :provider && self.class.suppress_provider?
      old_set_default.bind(self).call(attr)
    end

    def self.suppress_provider?
      @suppress_provider ||= false
    end

    def self.suppress_provider
      @suppress_provider = true
    end

    def self.unsuppress_provider
      @suppress_provider = false
    end
  end

  class Parser::TypeLoader
    old_try_load_fqname = instance_method(:try_load_fqname)

    define_method(:try_load_fqname) do |type, fqname|
      Puppet::Util::Platform.without_pretending do
        old_try_load_fqname.bind(self).call(type, fqname)
      end
    end
  end

  # If Puppet::Node::Environment has a validate_dirs instance method (i.e.
  # Puppet < 3.x), wrap the method to check if rspec-puppet is pretending to be
  # running under windows. The original method uses Puppet::Util.absolute_path?
  # (which in turn calls Puppet::Util::Platform.windows?) to validate the path
  # to the manifests on disk during compilation, so we have to temporarily
  # disable the pretending when running it.
  class Node::Environment
    if instance_methods.include?("validate_dirs")
      old_validate_dirs = instance_method(:validate_dirs)

      define_method(:validate_dirs) do |dirs|
        Puppet::Util::Platform.without_pretending do
          old_validate_dirs.bind(self).call(dirs)
        end
      end
    end
  end

  module Parser::Files
    if method_defined?(:find_in_module)
      old_find_in_module = method(:find_in_module)

      def find_in_module(*args)
        Puppet::Util::Platform.without_pretending do
          old_find_in_module.bind(self).call(*args)
        end
      end
      module_function :find_in_module
    end

    if method_defined?(:split_file_path)
      old_split_file_path = method(:split_file_path)

      def split_file_path(*args)
        Puppet::Util::Platform.without_pretending do
          old_split_file_path.bind(self).call(*args)
        end
      end
      module_function :split_file_path
    end
  end

  module Util
    # Allow rspec-puppet to pretend to be windows.
    module Platform
      def windows?
        pretend_platform.nil? ? !!File::ALT_SEPARATOR : pretend_windows?
      end
      module_function :windows?

      def pretend_windows?
        pretend_platform == :windows
      end
      module_function :pretend_windows?

      def pretend_to_be(platform)
        @pretend_platform = platform
        stub_consts_for(platform)
      end
      module_function :pretend_to_be

      def pretend_platform
        @pretend_platform ||= nil
      end
      module_function :pretend_platform

      def real_platform
        Gem.win_platform? ? :windows : :nix
      end
      module_function :real_platform

      def without_pretending
        pretending_to_be = pretend_platform

        if pretending_to_be
          pretend_to_be nil
        end

        stub_consts_for(real_platform)

        output = yield

        pretend_to_be(pretending_to_be)

        output
      end
      module_function :without_pretending

      def stub_consts_for(platform)
        if platform == :windows
          stub_const('PATH_SEPARATOR', ';')
          stub_const('ALT_SEPARATOR', "\\")
        else
          stub_const('PATH_SEPARATOR', ':')
          stub_const('ALT_SEPARATOR', nil)
        end
      end
      module_function :stub_consts_for

      def stub_const(const, value)
        File.send(:remove_const, const) if File.const_defined?(const)
        File.const_set(const, value)
      end
      module_function :stub_const
    end
  end
end

# Prevent Puppet from requiring 'puppet/util/windows' if we're pretending to be
# windows, otherwise it will require other libraries that probably won't be
# available on non-windows hosts.
module Kernel
  alias :old_require :require
  def require(path)
    return if path == 'puppet/util/windows' && Puppet::Util::Platform.pretend_windows?
    old_require(path)
  end
end
