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
config = node["ceph"]["osd"]

prepare="ceph-disk prepare --cluster #{cluster} --cluster-uuid #{node["ceph"]["config"]["global"]["fsid"]}"
prepare << " --fs-type #{config["fstype"]}"
prepare << " --dmcrypt" if config["encrypt"]
prepare << " --journal-file" if config["journal"] == "file"
prepare << " --journal-dev" if config["journal"] == "separate"


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

# Partition the disks into SSD vs. non-SSD
# In the normal course of things, we will force SSDs to be
journal = []
storage = []
storage_new = []
Disk.all.each do |d|
  Chef::Log.info("Disk #{d.unique_name} owned by #{d.owner(node) || "nobody"}")
  case
  when d.owner(node) == "ceph journal" then journal << d
  when d.owner(node) == "ceph storage" then storage << d
  when d.owner(node) then next
  when d.usb
    Chef::Log.info("Disk #{d.unique_name} attached via USB.  Ignoring.")
    next
  when d.removable
    Chef::Log.info("Disk #{d.unique_name} is removable.  Ignoring.")
  when d.held
    Chef::Log.info("Disk #{d.unique_name} is used as backing store for a RAID or LVM PV.  Ignoring.")
    next
  when d.partitioned
    Chef::Log.info("Disk #{d.unique_name} has partitions on it.  Ignoring.")
    next
  when d.formatted
    Chef::Log.info("Disk #{d.unique_name} has a filesystem on it.  Ignoring.")
    next
  when d.ssd && config["journal"] == "separate"
    Chef::Log.info("Disk #{d.unique_name} is an SSD.  Using it for journal storage.")
    d.own(node,"ceph journal")
    journal << d
  else
    Chef::Log.info("Using #{d.unique_name} for OSD bulk storage.")
    d.own(node,"ceph storage")
    storage_new << d
  end
end

if storage.empty? && storage_new.empty?
  raise "#{node[:fqdn]} cannot be a Ceph OSD, it does not have enough disks!"
end

if config["journal"] == "separate" && journal.empty?
  raise "No journal devices, cannot continue!" unless node[:ceph][:osd][:rusty_journal]
  Chef::Log.warn("Seperate journals requested for OSDs, but no SSD disks available!")
  d = storage_new.sort{|a,b|a.size <=> b.size}.first
  raise "No new storage volume to use for the separate journal!" unless d
  storage_new.delete(d)
  d.own(node,"ceph journal")
  journal << d
  Chef::Log.warn("Picked disk #{d.unique_name} instead")
end

storage.concat(storage_new)

osd_count = storage.length
min_osd_count = node[:ceph][:config][:global][:osd_pool_default_size]
if osd_count < min_osd_count
  raise "Not enough OSDs! Need #{min_osd_count}, have #{osd_count}"
end

storage.each do |d|
  next if d.partitioned
  ruby_block "Prepare new OSD #{d.unique_name}" do
    block do
      cmd = "#{prepare} #{d.unique_name}"
      d.mkgpt
      # Pick a journal device if we are running in separate journal mode
      # Always pick the one with the fewest partitions.
      if config["journal"] == "separate"
        j = journal.sort{|a,b|a.partitions.length <=> b.partitions.length}.first
        j.mkgpt
        Chef::Log.info("Disk #{d.unique_name} using journal on #{j.unique_name}")
        cmd << " #{j.unique_name}"
      end
      need_start = true
      Chef::Log.info("Ceph OSD: Preparing with #{cmd}")
      raise "Unable to create OSD on #{d.unique_name}" unless system "#{cmd}"
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
