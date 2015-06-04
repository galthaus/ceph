#
# Author:: Kyle Bader <kyle.bader@dreamhost.com>
# Cookbook Name:: ceph
# Recipe:: radosgw
#
# Copyright 2011, DreamHost Web Hosting
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

case node['platform_family']
when "debian"
  packages = %w{
    radosgw
  }

  #if node['ceph']['install_debug']
  #  packages_dbg = %w{
  #    radosgw-dbg
  #  }
  #  packages += packages_dbg
  #end
when "rhel","fedora","suse"
  packages = %w{
    ceph-radosgw
  }
end

packages.each do |pkg|
  package pkg do
    action :upgrade
  end
end
cluster = node[:ceph][:config][:global][:name]

rgw_user = (node[:ceph][:rgw][:user] rescue nil) || "radosgw"
radosgw_keyring = "/etc/ceph/#{cluster}.client.radosgw.#{node['hostname']}.keyring"

# Actually prime the radosgw to run on this system.
node.set[:ceph][:config]["client.radosgw.#{node['hostname']}"] = node[:ceph][:config]['client.radosgw']
node.set[:ceph][:config]["client.radosgw.#{node['hostname']}"]["host"] = node['hostname']
node.set[:ceph][:config]["client.radosgw.#{node['hostname']}"]["user"] = rgw_user
node.set[:ceph][:config]["client.radosgw.#{node['hostname']}"]["keyring"] = radosgw_keyring
user rgw_user do
  action :create
  system true
end

directory "/var/run/ceph" do
  action :create
  recursive true
  owner rgw_user
end

include_recipe "ceph::conf"

cmd = %W{ceph auth get-or-create client.radosgw.#{node['hostname']} 
         --cap osd 'allow rwx'
         --cap mon 'allow rw'
         --name client.admin
         '--key=#{node["ceph"]["admin"]}'
         -o '#{radosgw_keyring}'}.join(" ")

Chef::Log.info(cmd)

execute "create rados gateway client key" do
  cwd "/"
  creates radosgw_keyring
  command cmd
end

# Needed for radosgw-admin to work
execute "save ceph admin client key" do
  cwd "/"
  creates "/etc/ceph/#{cluster}.client.admin.keyring"
  command %W{ceph auth get-or-create client.admin
             --name client.admin
             '--key=#{node["ceph"]["admin"]}'
             -o '/etc/ceph/#{cluster}.client.admin.keyring'}.join(".")
end

ruby_block "Die if there is no key" do
  block do
    raise "Missing #{radosgw_keyring}"
  end
  not_if do ::File.exists?(radosgw_keyring) end
end

service "radosgw" do
  service_name "ceph-radosgw"
  supports :restart => true
  action [ :enable, :start ]
end
