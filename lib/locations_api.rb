require 'net/https'
require 'uri'
require 'json'
require 'date'
require 'parallel'

class LocationsApi
  attr_accessor :today, :cache

  @@cache = {}

  def get_cache
    @@cache
  end

  def set_cache(new_cache)
    @@cache = new_cache
  end

  def initialize
    @today = DateTime.now
    @days_of_the_week =  %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
    @location_data = nil
  end

  def fetch_data()
    locations_uri = URI('https://drupal.nypl.org/jsonapi/node/library?filter%5Bfield_ts_library_type%5D=research&page%5Boffset%5D=0&page%5Blimit%5D=125&sort=title&jsonapi_include=1')
    response = Net::HTTP.get_response(locations_uri)
    @location_data = JSON.parse(response.body, { symbolize_names: true })[:data]
    new_cache = {}
    @location_data.each do |branch|
      new_cache[branch[:field_ts_location_code].to_sym] = {
        slug: branch[:field_ts_slug],
        hours: build_hours_array(branch[:field_ohs_hours], @today),
        address: build_address(branch[:field_as_address])
      }
    end
    # update timestamp in cache
    new_cache[:last_cache_time] = @today.to_time.to_i
    new_cache
  end

  # Expects a location code in the format mal99. Returns a hash with a slug, hours, and address corresponding
  # to that location code. Before making an api call, checks cache.
  def get_location_data(location_code)
    new_cache = !@@cache.key?(:last_cache_time)
    cache_timed_out = !new_cache && @today.to_time.to_i - @@cache[:last_cache_time] > 3600
    if new_cache || cache_timed_out
      @@cache = fetch_data
    end
    trimmed_location_code = location_code[0..1].to_sym
    @@cache[trimmed_location_code]
  end

  def build_address(address_info)
    {
      'line1': address_info[:address_line1],
      'city': address_info[:locality],
      'state': address_info[:administrative_area],
      'postalCode': address_info[:postal_code]
    }
  end

  def arrange_days(hours_per_day, today_of_the_week)
    # make sure days are in correct order
    hours_per_day = hours_per_day.sort_by { |day| day[:day] }
    # find the day object that contains today
    day_index = hours_per_day.index { |day| day[:day] == @days_of_the_week.index(today_of_the_week) }
    # reorder day objects so today is first in the array
    if day_index.zero?
      hours_per_day
    else
      hours_per_day.slice(day_index..-1) + hours_per_day.slice(0..day_index - 1)
    end
  end

  def build_day_string(time, day)
    DateTime.new(day.year, day.month, day.day, time / 100, time % 100)
  end

  def build_hours_object(start_time, end_time, day, index)
    hours = {
      'day': day.strftime('%A'),
      'startTime': build_day_string(start_time, day).to_s,
      'endTime': build_day_string(end_time, day).to_s
    }
    hours[:today] = true if index.zero?
    hours[:nextBusinessDay] = true if index == 1
    hours
  end

  # build an an array with opening and closing timestamps for every day of the next week,
  # starting with today
  def build_hours_array(hours_per_day, current_day)
    # get the day of the week by human readable name
    today_of_the_week = current_day.strftime('%A')
    # arrange the hours per day array into an order starting with today_of_the_week
    arranged_hours_per_day = arrange_days(hours_per_day, today_of_the_week)
    # loop over that array, creating full timestamps for the hours provided using current_day.
    # current_day starts off as @today and is incremented as we iterate over the array.
    arranged_hours_per_day.map.with_index do |day, i|
      hours_object = build_hours_object(day[:starthours], day[:endhours], current_day, i)
      # .succ returns the next day
      current_day = current_day.succ
      hours_object
    end
  end
end
