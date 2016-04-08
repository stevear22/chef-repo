#
# Author:: John Keiser (<jkeiser@chef.io>)
# Copyright:: Copyright 2012-2016, Chef Software Inc.
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
#

require "chef/chef_fs/file_system/file_system_error"

class Chef
  module ChefFS
    module FileSystem
      class OperationNotAllowedError < FileSystemError
        def initialize(operation, entry, cause = nil, reason = nil)
          reason ||=
            case operation
            when :delete
              "cannot be deleted"
            when :write
              "cannot be updated"
            when :create_child
              "cannot have a child created under it"
            when :read
              "cannot be read"
            end
          super(entry, cause, reason)
          @operation = operation
        end

        attr_reader :operation
        attr_reader :entry
      end
    end
  end
end
