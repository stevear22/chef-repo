#
# Author:: John Keiser <jkeiser@chef.io>
# Copyright:: Copyright 2015-2016, Chef Software, Inc.
# License:: Apache License, Version 2.0
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

require "chef/dsl/cheffish"
require "chef/dsl/chef_provisioning"

class Chef
  module DSL
    #
    # Module containing a method for each globally declared Resource
    #
    # Depends on declare_resource(name, created_at, &block)
    #
    # @api private
    module Resources
      # Include the lazy loaders for cheffish and chef-provisioning, so that the
      # resource DSL is there but the gems aren't activated yet.
      include Chef::DSL::Cheffish
      include Chef::DSL::ChefProvisioning

      def self.add_resource_dsl(dsl_name)
        begin
          module_eval(<<-EOM, __FILE__, __LINE__ + 1)
            def #{dsl_name}(*args, &block)
              Chef.log_deprecation("Cannot create resource #{dsl_name} with more than one argument. All arguments except the name (\#{args[0].inspect}) will be ignored. This will cause an error in Chef 13. Arguments: \#{args}") if args.size > 1
              declare_resource(#{dsl_name.inspect}, args[0], caller[0], &block)
            end
          EOM
        rescue SyntaxError
          # Handle the case where dsl_name has spaces, etc.
          define_method(dsl_name.to_sym) do |*args, &block|
            Chef.log_deprecation("Cannot create resource #{dsl_name} with more than one argument. All arguments except the name (#{args[0].inspect}) will be ignored. This will cause an error in Chef 13. Arguments: #{args}") if args.size > 1
            declare_resource(dsl_name, args[0], caller[0], &block)
          end
        end
      end

      def self.remove_resource_dsl(dsl_name)
        remove_method(dsl_name)
      rescue NameError
      end
    end
  end
end
