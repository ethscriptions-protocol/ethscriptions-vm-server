class StatusController < ApplicationController
  def vm_status
    oldest_ethscription = Ethscription.oldest_first.first
    newest_ethscription = Ethscription.newest_first.first
    
    if newest_ethscription.nil?
      render json: { error: "No ethscriptions found" }
      return
    end
    
    total_newer_ethscriptions = Rails.cache.read("future_ethscriptions").to_i
        
    resp = {
      oldest_known_ethscription: oldest_ethscription,
      newest_known_ethscription: newest_ethscription,
      ethscriptions_behind: total_newer_ethscriptions
    }
        
    render json: resp
  end
end
