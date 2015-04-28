raise "fsid must be set in config" if node["ceph"]["config"]['fsid'].nil?

mons = node["ceph"]["monitors"]

is_rgw = false
if node['roles'].include? 'ceph-radosgw'
  is_rgw = true
end

directory "/etc/ceph" do
  owner "root"
  group "root"
  mode "0755"
  action :create
end

template '/etc/ceph/ceph.conf' do
  source 'ceph.conf.erb'
  variables(
    :mons => mons,
    :is_rgw => is_rgw,
    :frontend => IP.coerce(node["ceph"]["config"]["addresses"]["frontend"]),
    :backend => IP.coerce(node["ceph"]["config"]["addresses"]["backend"])
  )
  mode '0644'
end
