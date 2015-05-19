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
      Rails.logger.info("#{name}: Merging cluster secret keys into #{dr.deployment.name}")
      dr.data_update({"ceph" => {"monitor-secret" => BarclampCeph.genkey}})
      dr.commit
      Rails.logger.info("Merged.")
    end
  end

  def sysdata(nr)
    mons={}
    mons_cfg = {}
    mon_initial_members = []
    nr.role.node_roles.where(:deployment_id => nr.deployment_id).each do |t|
      addr = Attrib.get("ceph-frontend-address",t.node)
      next unless addr
      mon_name = t.node.name.split(".")[0]
      mon_initial_members << mon_name
      mons[t.node.name]={"address" => IP.coerce(addr).addr, "name" => mon_name}
      mons_cfg["mon.#{mon_name}"] = {
        "host" => mon_name,
        "mon addr" => "[#{IP.coerce(addr).addr}]:6789"
      }
    end
    mons_cfg["global"] = {"mon_initial_members" => mon_initial_members.sort.join(",")}

    {"ceph" => {
       "monitors" => mons,
       "config" => mons_cfg
      }
    }
  end

end
