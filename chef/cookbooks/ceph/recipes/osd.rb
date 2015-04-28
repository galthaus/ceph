#
# Author:: Kyle Bader <kyle.bader@dreamhost.com>
# Cookbook Name:: ceph
# Recipe:: osd
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

# this recipe allows bootstrapping new osds, with help from mon
# Sample environment:
# #knife node edit ceph1
#"osd_devices": [
#   {
#       "device": "/dev/sdc"
#   },
#   {
#       "device": "/dev/sdd",
#       "dmcrypt": true,
#       "journal": "/dev/sdd"
#   }
#]

include_recipe "ceph::default"
include_recipe "ceph::conf"

package 'gdisk' do
  action :upgrade
end

package 'cryptsetup' do
  action :upgrade
end

directory "/var/lib/ceph/bootstrap-osd" do
  owner "root"
  group "root"
  mode "0755"
end

# TODO cluster name
cluster = cluster_name
config = node["ceph"]["config"]["osd"]

prepare="ceph-disk prepare --cluster #{cluster} --cluster-uuid #{node["ceph"]["config"]["fsid"]}"
prepare << " --fs-type #{config["fstype"]}"
prepare << " --dmcrypt" if config["encrypt"]
prepare << " --journal-file" if config["journal"] == "file"


osd_secret = if node['ceph']['encrypted_data_bags']
               secret = Chef::EncryptedDataBagItem.load_secret(node["ceph"]["osd"]["secret_file"])
               Chef::EncryptedDataBagItem.load("ceph", "osd", secret)["secret"]
             else
               node["ceph"]["bootstrap-osd"]
             end

keyring = "/var/lib/ceph/bootstrap-osd/#{cluster}.keyring"

execute "format as keyring" do
  command "ceph-authtool '#{keyring}' --create-keyring --name=client.bootstrap-osd --add-key='#{osd_secret}'"
  creates keyring
  not_if do File.exists?(keyring) end
end

need_start = false

ruby_block "select new disks for ceph osd" do
  block do
    node.disks.each do |name,disk|
      next unless disk["available"] && !node.reserved_disk?(name) && !disk["usb"]
      next unless node.reserve_disk(name,"ceph-osd")
      need_start = true
      Chef::Log.info("Ceph OSD: Preparing with #{prepare} /dev/#{name}")
      system "#{prepare} /dev/#{name}"
    end
  end
end

service "ceph" do
  action [ :enable, :start ]
  supports :restart => true
end

execute "start all osds" do
  command "ceph-disk activate-all"
end
