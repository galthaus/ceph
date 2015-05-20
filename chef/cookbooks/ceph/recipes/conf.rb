raise "fsid must be set in config" if node["ceph"]["config"]["global"]['fsid'].nil?

# Get our standard config parameters in an easy-to-digest format
frontend_net = IP.coerce(node["ceph"]["addresses"]["frontend"]).network.to_s
backend_net = IP.coerce(node["ceph"]["addresses"]["backend"]).network.to_s
node.set["ceph"]["config"]["global"]["public_network"] = frontend_net
if frontend_net != backend_net
  node.set["ceph"]["config"]["global"]["cluster_network"] = backend_net
end

directory "/etc/ceph" do
  owner "root"
  group "root"
  mode "0755"
  action :create
end

# Figure out the order in which top-level config keys should be written
# in the config file.
globalparts = %w{global osd mon mds client}
keys = node["ceph"]["config"].keys
order = []

# First, pick off the known global config and global daemon parts, and
# process then in the proper order.
globalparts.each do |k|
  next unless keys.delete(k)
  order << k
end

# Second, sort out unknown global daemon parts and local daemon parts
keys.sort.partition{|k| k.include?(".")}.each{|a| order.concat(a)}

template '/etc/ceph/ceph.conf' do
  source 'ceph.conf.erb'
  variables :order => order
  mode '0644'
end
