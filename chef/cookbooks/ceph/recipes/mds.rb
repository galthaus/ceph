#
# Author:: Kyle Bader <kyle.bader@dreamhost.com>
# Cookbook Name:: ceph
# Recipe:: mds
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

raise "Ceph MDS recipe not implemented for Crowbar right now"

include_recipe "ceph::default"
include_recipe "ceph::conf"

service_type = node["ceph"]["mds"]["init_style"]

directory "/var/lib/ceph/bootstrap-mds" do
  owner "root"
  group "root"
  mode "0755"
end

# TODO cluster name
cluster = cluster_name
config = node["ceph"]["config"]["mds"]

mds_bootstrap_secret = if node['ceph']['encrypted_data_bags']
                         secret = Chef::EncryptedDataBagItem.load_secret(node["ceph"]["mds"]["secret_file"])
                         Chef::EncryptedDataBagItem.load("ceph", "mds", secret)["secret"]
                       else
                         node["ceph"]["bootstrap-mds"]
                       end

bootstrap_keyring = "/var/lib/ceph/bootstrap-mds/#{cluster}.keyring"

execute "format as keyring" do
  command "ceph-authtool '#{bootstrap_keyring}' --create-keyring --name=client.bootstrap-mds --add-key='#{mds_bootstrap_secret}'"
  creates bootstrap_keyring
  not_if do File.exists?(bootstrap_keyring) end
end

mds_dir = "/var/lib/ceph/mds/#{cluster}-#{node['hostname']}"
mds_keyring = File.join(mds_dir,"keyring")
# Create a new key for this MDS
directory mds_dir do
  owner "root"
  group "root"
  mode "0755"
end

create_command = "ceph --cluster #{cluster} --name client.bootstrap-mds --keyring #{bootstrap_keyring}"
create_command << " auth get-or-create mds.#{node["hostname"]}"
create_command << " osd 'allow rwx'"
create_command << " mds allow"
create_command << " mon 'allow profile mds'"
create_command << " -o #{mds_keyring}"

execute "Create local MDS key" do
  command create_command
  creates mds_keyring
  not_if do File.exists?(mds_keyring) end
end

[service_type,"done"].each do |f|
  file File.join(mds_dir,f) do
    action :create_if_missing
  end
end

service "ceph_mds" do
  case service_type
  when "upstart"
    service_name "ceph-mds-all-starter"
    provider Chef::Provider::Service::Upstart
  else
    service_name "ceph"
  end
  action [ :enable, :start ]
  supports :restart => true
end

# rest of recipe coming soon
