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

class BarclampCeph::Config < Role
  def on_deployment_create(dr)
    DeploymentRole.transaction do
      Rails.logger.info("#{name}: Creating bootstrap cluster config")
      Attrib.set("ceph-fs_uuid",dr,%x{uuidgen}.strip)
      dr.commit
    end
  end

  def on_node_bind(nr)
    nets = ceph_nets(nr)
    nets.each do |net|
      next if NetworkAllocation.find_by(network: net, node: nr.node)
      net_nr = net.make_node_role(nr.node)
      net_nr.add_child(nr)
    end
  end

  def on_todo(nr)
    frontend_net, backend_net = ceph_nets(nr)
    Attrib.set("ceph-frontend-address",nr,
               NetworkAllocation.find_by(network: frontend_net, node: nr.node).address.to_s)
    Attrib.set("ceph-backend-address",
               nr,
               NetworkAllocation.find_by(network: backend_net, node: nr.node).address.to_s)
  end

  private

  def ceph_nets(obj)
    # We always want to know that our frontend and backend networks
    # exist.
    frontend_name = Attrib.get("ceph-frontend-net",obj)
    backend_name = Attrib.get("ceph-backend-net",obj)
    frontend_net = Network.find_by(name: frontend_name)
    backend_net = Network.find_by(name: backend_name)
    if frontend_net.nil?
      raise MISSING_DEP.new("#{self.name} wants frontend network #{frontend_name}, but it does not exist!")
    end
    if backend_net.nil?
      raise MISSING_DEP.new("#{self.name} wants backend network #{backend_name}, but it does not exist!")
    end
    [frontend_net, backend_net]
  end
end
