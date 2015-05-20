# Copyright 2015, RackN
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
#

class ::BarclampCeph::Attrib::CephAll < Attrib

  def get(data, source=:all, committed=false)
    Attrib.transaction do
      from = __resolve(data)
      res = {}
      raise "Aieee" if data.is_a?(Hash)
      Rails.logger.info("#{self.class.name}: Resolving all ceph data for #{from.name}")
      case
      when from.is_a?(NodeRole)
        res = from.attrib_data
        dd = {}
        ud = {}
        sd = {}
        wd = {}
        ad = {}
        from.children.where(deployment_id: from.deployment_id).each do |cnr|
          dd.deep_merge!(cnr.deployment_role.all_data(committed))
          ud.deep_merge!(cnr.committed_data)
          ud.deep_merge!(cnr.proposed_data) unless committed
          sd.deep_merge!(cnr.sysdata)
          wd.deep_merge!(cnr.wall)
          ad = dd.deep_merge(wd).deep_merge(sd).deep_merge(ud)
          cnr.attribs.each do |ca|
            next if ca.id = self.id
            ad.deep_merge!(ca.extract(ad))
          end
        end
        res.deep_merge!(ad)
        res.deep_merge!(from.attrib_data)
      when from.is_a?(DeploymentRole)
        res = from.all_data(committed)
      end
      from.attribs.each do |attr|
        next if attr.id == self.id
        res.deep_merge!(attr.extract(res))
      end
      super(res, source)
    end
  end
end
