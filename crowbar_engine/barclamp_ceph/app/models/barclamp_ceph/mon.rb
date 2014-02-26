# Copyright 2013, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

class BarclampCeph::Mon < Role

  def on_deployment_create(dr)
    DeploymentRole.transaction do
      d = dr.data
      Rails.logger.info("#{name}: Merging cluster secret keys into #{dr.deployment.name} (#{d.inspect})")
      d.deep_merge!({"ceph" => {"monitor-secret" => BarclampCeph.genkey}})
      Rails.logger.info("Merged.")
      dr.data = d
      dr.save!
    end
  end

  def sysdata(nr)
    mon_nodes = Hash.new
    net = Network.where(:name => "ceph").first
    nr.role.node_roles.where(:snapshot_id => nr.snapshot_id).each do |t|
      addr = t.node.auto_v6_address(net).addr
      mon_nodes[t.node.name] = { "address" => addr, "name" => t.node.name.split(".")[0]}
    end

    {"ceph" => {
        "monitors" => mon_nodes
      }
    }
  end

end
