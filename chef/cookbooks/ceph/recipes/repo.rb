raise "Repo not needed for OpenCrowbar"

return
case node['platform_family']
when "debian"
  include_recipe "ceph::apt"
when "rhel", "suse"
  include_recipe "ceph::rpm"
else
  raise "not supported"
end 
