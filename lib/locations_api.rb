require 'net/https'
require 'uri'
require 'json'
require 'date'

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
    @days_of_the_week = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
    @location_data = nil
  end

  def fetch_data()
    locations_uri = URI('https://drupal.nypl.org/jsonapi/node/library?filter%5Bfield_ts_library_type%5D=research&page%5Boffset%5D=0&page%5Blimit%5D=125&sort=title&jsonapi_include=1')
    # for an example of api response, see spec/fixtures/location_api.json
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
  #     example return value:
  #   {slug: 'schwarzman',
  #    hours: [{startTime: '2023-06-01T10:00:00+00:00',
  #             endtime: '2023-06-01T18:00:00+00:00',
  #             day: 'Thursday',
  #             today: 'true'},...(5)],
  #    address:  {
  #                'line1': 'Fifth Avenue and 42nd Street',
  #                'city': 'New York',
  #                'state': 'NY',
  #                'postalCode': '10018'
  #              }
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

  # Expects an array of hashes representing open days of the branch. Returns an
  # array of those days in order, rearranged to start with today_of_the_week. 
  # hours_per_day can have up to 7 elements, but can have less. 
  # With parameters:
  #   [{day: 0, starthours: 1000, endhours: 1800},
  #    {day: 1, starthours: 1000, endhours: 1800},
  #   ...
  #    {day: 5, starthours: 1000, endhours: 1800}], 'Tuesday'
  # returns:
  #   [{day: 2, starthours: 1000, endhours: 1800},
  #    {day: 3, starthours: 1000, endhours: 1800},
  #    {day: 4, starthours: 1000, endhours: 1800},
  #    {day: 5, starthours: 1000, endhours: 1800},
  #    {day: 0, starthours: 1000, endhours: 1800},
  #    {day: 1, starthours: 1000, endhours: 1800}]
  def arrange_days(hours_per_day, today_of_the_week)
    # make sure days are in correct order. the day property is a number 0-6
    hours_per_day = hours_per_day.sort_by { |day| day[:day] }
    # find the day object that corresponds to today_of_the_week
    day_index = hours_per_day.index { |day| day[:day] == @days_of_the_week.index(today_of_the_week) }
    # reorder day objects so today is first in the array
    if day_index.zero?
      hours_per_day
    else
      hours_per_day.slice(day_index..-1) + hours_per_day.slice(0..day_index - 1)
    end
  end

  def build_timestamp(time, day)
    DateTime.new(day.year, day.month, day.day, time / 100, time % 100)
  end

  def build_hours_hash(start_time, end_time, day, index)
    hours = {
      'day': day.strftime('%A'),
      'startTime': build_timestamp(start_time, day).to_s,
      'endTime': build_timestamp(end_time, day).to_s
    }
    hours[:today] = true if index.zero?
    hours[:nextBusinessDay] = true if index == 1
    hours
  end

  # Takes an array of hours_per_day objects and returns an array rearranged
  # and having transformed hours into date time strings. For example:
  #   [{startTime: '2023-06-01T10:00:00+00:00',
  #     endtime: '2023-06-01T18:00:00+00:00',
  #     day: 'Thursday',
  #     today: 'true'},
  #   {startTime: '2023-06-02T10:00:00+00:00',
  #     endtime: '2023-06-02T18:00:00+00:00',
  #     day: 'Friday',
  #     today: 'true'},
  #     ...
  #   {startTime: '2023-06-07T10:00:00+00:00',
  #     endtime: '2023-06-07T18:00:00+00:00',
  #     day: 'Tuesday',
  #     today: 'true'},
  #    {startTime: '2023-06-08T10:00:00+00:00',
  #     endtime: '2023-06-08T18:00:00+00:00',
  #     day: 'Wednesday'}]
  def build_hours_array(hours_per_day, current_day)
    # get the day of the week by human readable name
    today_of_the_week = current_day.strftime('%A')
    # arrange the hours per day array into an order starting with today_of_the_week
    arranged_hours_per_day = arrange_days(hours_per_day, today_of_the_week)
    # loop over that array, creating full timestamps for the start and endhours using 
    # current_day as the date. current_day starts off as @today and is incremented 
    # by one day for each iteration of the array.
    arranged_hours_per_day.map.with_index do |day, i|
      hours_hash = build_hours_hash(day[:starthours], day[:endhours], current_day, i)
      # .succ returns the next day
      current_day = current_day.succ
      hours_hash
    end
  end
end
