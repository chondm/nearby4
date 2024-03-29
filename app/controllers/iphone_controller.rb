include Geokit::Geocoders
require 'json'
require 'open-uri'

class IphoneController < ApplicationController
  
  respond_to :html, :xml, :json, :js
  
  RADIUS = '750'  
  DEFAULT_LOCATION = 'Atlanta, GA' 
  
  def iphone
    if !params[:lat].blank? && !params[:lng].blank?
      coordinates = [params[:lat].to_f, params[:lng].to_f]
      locations = Location.near(coordinates, 2)
      
      begin
        near_your_locations = HTTParty.get("https://maps.googleapis.com/maps/api/place/search/json?location=#{coordinates.join(',')}&types=&radius=#{RADIUS}&sensor=false&key=AIzaSyA1mwwvv3NAL_N7gNRf_0uqK2pfiXEqkZc")
      rescue
      end
      xml_res = Array.new
      
      locations.each do |location|
        xml_res += [:name => location.name, :location => location.address,
          :reference => location.reference]
      end
      
      near_your_locations['results'].each do |location|
        xml_res += [:name => location['name'], :location => location['vicinity'],
          :reference => location['reference']]
      end
      
      render :xml => xml_res
    else
      render :layout => false
    end
  end
 
  def iphone_details
    reference = params[:reference]    
    details = get_place_response(reference)    
    
    location = Location.find_by_reference(reference)   
    xml_res = Array.new
    xml_res += [:address => params[:address]]
    xml_res += [:details => details]
    lat, long = ""
    unless location.blank?
      xml_res += [:lastest_tweet => get_last_tweet(location.twitter_name)]
      xml_res += [:lastest_post => get_last_post(location)]
      xml_res += [:user_metion => get_tweet_search(location.twitter_name)]
    end
    
    unless location.blank?
      lat,long = location.latitude, location.longitude
    else
      lat, long = details['result']['geometry']['location']['lat'], details['result']['geometry']['location']['lng'] unless details.blank?    
    end
    
    xml_res += [:lat => lat, :lng => long]
    
    advertise = get_logo(details, location)  
    xml_res += [:logo_url => advertise.blank? ? nil : advertise.photo.url(:medium)]
       
    
    render :xml => xml_res
  end
  
  
  private
  
  def get_logo(details, location)   
    adv = nil
    unless location.blank?      
      adv = Advertise.where("address_name like '%#{location.city}, #{location.state}%' and business_name like '%#{location.name}%' ").first();      
      adv = Advertise.where("business_name like '%#{location.name}%'").first() if adv.blank?
      adv = Advertise.where("address_name like '%#{location.city}, #{location.state}%'").first() if adv.blank?
      adv = Advertise.where("business_type = '#{location.types}'").first() if adv.blank?
    else
      loc = details['result']       
      if loc['vicinity'] != nil && loc['name'] != nil
        add, city = loc['vicinity'].split(",")          
        adv = Advertise.where("(address_name like '%#{city.strip}%' or address_name like '%#{add.strip}%') and business_name like '%#{loc['name']}%' ").first()
        adv = Advertise.where("business_name like '%#{loc['name']}%'").first() if adv.blank?          
      end      
    end
    return adv
  end
  

  def types(general_type)
    results = ""
    if general_type.eql?("Eat/Drink")
      results = eat_drink
    elsif general_type.eql?("Relax/Care")
      results = relax_care
    elsif general_type.eql?("Shop/Find")
      results = shop_find
    end
    results
  end
    
  def get_general_type(type)    
    return "Eat/Drink" if eat_drink.include?(type)
    return "Relax/Care" if relax_care.include?(type)
    return "Shop/Find" if shop_find.include?(type)
  end
  
  def get_facebook_feed(facebook_page_id)
    begin
      # convert real name to id
      res_page = RestClient.get "https://graph.facebook.com/#{facebook_page_id}"
      result_page = ActiveSupport::JSON.decode(res_page) 
      
      facebook_link = "http://www.facebook.com/feeds/page.php?id=#{result_page["id"]}&format=json"
      res = RestClient.get facebook_link
      return ActiveSupport::JSON.decode(res)
    rescue
    end    
  end
  
  def get_twitter_feed(twitter_name)
    begin
      twitter_link = "http://api.twitter.com/1/statuses/user_timeline.json?screen_name=#{twitter_name}"
      timeline = RestClient.get twitter_link
      return ActiveSupport::JSON.decode(timeline)
    rescue
    end
  end
  
  def get_place_report(location, long, lat)    
    myarray = {:location => {:lat => lat.to_f, :lng => long.to_f},
      :accuracy => 50, :name => location[:name], 
      :types => [location[:types]], :language => "en-AU"}
    json_string = myarray.to_json()    
    res = RestClient.post "https://maps.googleapis.com/maps/api/place/add/json?sensor=false&key=AIzaSyA1mwwvv3NAL_N7gNRf_0uqK2pfiXEqkZc", json_string, :content_type => :json, :accept => :json    
    ActiveSupport::JSON.decode(res)
  end
  
  def get_place_response(reference)
    HTTParty.get("https://maps.googleapis.com/maps/api/place/details/json?reference=#{reference}&sensor=true&key=AIzaSyA1mwwvv3NAL_N7gNRf_0uqK2pfiXEqkZc")
  end
  
  def get_last_post(location)    
    unless location.facebook_page_id.blank?
      # convert real name to id  
      id = location.facebook_page_id
      if is_real_name(location.facebook_page_id)
        res_page = RestClient.get "https://graph.facebook.com/#{location.facebook_page_id}"
        result_page = ActiveSupport::JSON.decode(res_page) 
        id = result_page["id"]
      end
      
      facebook_link = "http://www.facebook.com/feeds/page.php?id=#{id}&format=json"
      res = RestClient.get facebook_link
      results = ActiveSupport::JSON.decode(res)
      
      return results["entries"].first["title"] unless results["entries"].blank?
    end
  end
  
  def get_last_tweet(user_name)    
    timeline = RestClient.get "http://api.twitter.com/1/statuses/user_timeline.json?screen_name=#{user_name}&count=1"
    ActiveSupport::JSON.decode(timeline)    
  end
  
  def get_tweet_search(bussiness_name) 
    tweet = RestClient.get  "http://search.twitter.com/search.json?q=@#{bussiness_name.gsub(" ", "+")}&count=10"    
    ActiveSupport::JSON.decode(tweet)    
  end
  
  def is_real_name(name)
    name.to_i == 0? true : false
  end
  
  def eat_drink
    return ["bar", "cafe", "food", "restaurant"]
  end
  
  def relax_care
    ["amusement park", "aquarium", "art gallery", "beauty salon", "bowling alley",
      "casino", "gym", "hair care", "health", "movie theater", "museum", "night club", "park", "spa", "zoo"]
  end
  
  def shop_find
    ["atm", "bank", "bicycle store", "book store", "bus station", "clothing store", "convenience store" ,
      "department store", "electronics store", "establishment", "florist", "gas station", "grocery or supermarket",
      "hardware store", "home goods store", "jewelry store", "library", "liquor store", "locksmith", "pet store",
      "pharmacy", "shoe store", "shopping mall", "store"]
  end
  
  def get_types(types)
    results = ""
    if types.eql?("Eat/Drink")
      results = "bar%7Ccafe%7Crestaurant%7Cfood"
    elsif types.eql?("Relax/Care")
      results = "aquarium%7Cart_gallery%7Cbeauty_salon%7Cbowling_alley," +
        "casino%7Cgym%7Cmovie_theater%7Cmuseum%7Cnight_club%7Cpark%7Cspa"
    elsif types.eql?("Shop/Find")
      results = "clothing_store%7Cshoe_store%7Cconvenience_store"
    end
    results
  end
end
