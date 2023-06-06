require 'webmock/rspec'
require_relative '../lib/locations_api'

describe LocationsApi do
  before(:each) do
    @test_locations_api = LocationsApi.new

    @today = DateTime.new(2023, 6, 1, 9, 0)
    @test_locations_api.today = @today
  end

  describe '#fetch_data' do
    it 'should populate cache per branch' do
      stub_request(:get, 'https://drupal.nypl.org/jsonapi/node/library?filter%5Bfield_ts_library_type%5D=research&page%5Boffset%5D=0&page%5Blimit%5D=125&sort=title&jsonapi_include=1')
        .to_return(status: 200, body: File.read('spec/fixtures/location_api.json'))
      cache = @test_locations_api.fetch_data
      expect(cache.keys).to eq([:sc, :ma, :my, :last_cache_time])
      expect(cache[:ma][:address]).to eq({ line1: 'Fifth Avenue and 42nd Street', city: 'New York', state: 'NY', postalCode: '10018' })
      expect(cache[:ma][:slug]).to eq('schwarzman')
      expect(cache[:ma][:hours]).to eq([
        { day: 'Thursday', startTime: '2023-06-01T10:00:00+00:00',
          endTime: '2023-06-01T18:00:00+00:00', today: true, nextBusinessDay: false },
        { day: 'Friday', startTime: '2023-06-02T10:00:00+00:00',
          endTime: '2023-06-02T18:00:00+00:00', today: false, nextBusinessDay: true },
        { day: 'Saturday', startTime: '2023-06-03T10:00:00+00:00',
          endTime: '2023-06-03T18:00:00+00:00', today: false, nextBusinessDay: false },
        { day: 'Sunday', startTime: '2023-06-04T13:00:00+00:00',
          endTime: '2023-06-04T17:00:00+00:00', today: false, nextBusinessDay: false  },
        { day: 'Monday', startTime: '2023-06-05T10:00:00+00:00',
          endTime: '2023-06-05T18:00:00+00:00', today: false, nextBusinessDay: false  },
        { day: 'Tuesday', startTime: '2023-06-06T10:00:00+00:00',
          endTime: '2023-06-06T20:00:00+00:00', today: false, nextBusinessDay: false  },
        { day: 'Wednesday', startTime: '2023-06-07T10:00:00+00:00',
          endTime: '2023-06-07T20:00:00+00:00', today: false, nextBusinessDay: false  }
      ])

      expect(cache[:last_cache_time]).to eq(@today.to_time.to_i)
    end
  end

  describe 'get_location_data' do
    it 'should fetch_data if cache was populated more than one hour ago' do
      # set last_cache_time to two hours before @today
      @test_locations_api.set_cache({
        last_cache_time: (@today - (2/24.0)).to_time.to_i,
        sc: 'cached_value'
      })
      allow(@test_locations_api).to receive(:fetch_data).and_return({sc: 'data from api'})
      expect(@test_locations_api.get_location_data('sc456')).to eq 'data from api'
    end
    it 'should access the cache if it was populated less than one hour ago' do
      # set last cache time to twenty minutes before @today
      @test_locations_api.set_cache({
        last_cache_time: (@today - (20 / 1440.0)).to_time.to_i,
        sc: 'cached_value'
      })
      new_cache = @test_locations_api.get_location_data('sc123')
      expect(new_cache).to eq 'cached_value'
      expect(@test_locations_api.get_cache[:last_cache_time]).to eq (@today - (20 / 1440.0)).to_time.to_i
    end
    it 'should access the same cache when api is reinstatiated' do
      new_api = LocationsApi.new
      new_api.today = @today
      expect(new_api.get_location_data('sc123')).to eq 'cached_value'
      expect(new_api.get_cache[:last_cache_time]).to eq (@today - (20 / 1440.0)).to_time.to_i
    end
  end

  describe '#arrange_days' do
    it 'should arrange the days so the first day is today_of_the_week' do
      hours_per_day = [{ day: 1 }, { day: 2 }, { day: 3 }, { day: 4 }, { day: 5 }, { day: 6 },
                       { day: 0 }]
      today_of_the_week = 'Wednesday'
      order = @test_locations_api.arrange_days(hours_per_day, today_of_the_week)
                                 .map { |day| day[:day] }
      expect(order).to eq [3, 4, 5, 6, 0, 1, 2]
    end
    it 'should arrange the days correctly, unsorted hours array, today is Sunday' do
      hours_per_day = [{ day: 6 }, { day: 4 }, { day: 2 }, { day: 3 }, { day: 5 }, { day: 0 },
                       { day: 1 }]
      today_of_the_week = 'Sunday'
      order = @test_locations_api.arrange_days(hours_per_day, today_of_the_week)
                                 .map { |day| day[:day] }
      expect(order).to eq [0, 1, 2, 3, 4, 5, 6]
    end
    it 'should arrange the days correctly, unsorted hours array, 5 day week' do
      hours_per_day = [{ day: 6 }, { day: 4 }, { day: 2 }, { day: 3 }, { day: 5 }]
      today_of_the_week = 'Friday'
      order = @test_locations_api.arrange_days(hours_per_day, today_of_the_week)
                                 .map { |day| day[:day] }
      expect(order).to eq [5, 6, 2, 3, 4]
    end
  end

  describe '#build_day_string' do
    it 'should return day with new time' do
      time = 1350
      day = DateTime.now
      built_day = @test_locations_api.build_day_string(time, day)
      expect(built_day.to_s).to include('T13:50')
    end
  end

  describe '#build_hours_array' do
    it 'should build hours array' do
      hours_per_day = [
        # sunday
        { day: 0, all_day: false, starthours: 1300, endhours: 1700, comment: '' },
        # monday
        { day: 1, all_day: false, starthours: 1000, endhours: 1800, comment: '' },
        # tuesday
        { day: 2, all_day: false, starthours: 1000, endhours: 2000, comment: '' },
        # wednesday
        { day: 3, all_day: false, starthours: 1000, endhours: 2000, comment: '' },
        # thursday
        { day: 4, all_day: false, starthours: 1000, endhours: 1800, comment: '' },
        # friday
        { day: 5, all_day: false, starthours: 1000, endhours: 1800, comment: '' },
        # saturday
        { day: 6, all_day: false, starthours: 1000, endhours: 1800, comment: '' }
      ]
      hours_array = @test_locations_api.build_hours_array(hours_per_day, @today)
      expect(hours_array).to eq [
        { day: 'Thursday', startTime: '2023-06-01T10:00:00+00:00',
          endTime: '2023-06-01T18:00:00+00:00', today: true, nextBusinessDay: false },
        { day: 'Friday', startTime: '2023-06-02T10:00:00+00:00',
          endTime: '2023-06-02T18:00:00+00:00', today: false, nextBusinessDay: true },
        { day: 'Saturday', startTime: '2023-06-03T10:00:00+00:00',
          endTime: '2023-06-03T18:00:00+00:00', today: false, nextBusinessDay: false },
        { day: 'Sunday', startTime: '2023-06-04T13:00:00+00:00',
          endTime: '2023-06-04T17:00:00+00:00', today: false, nextBusinessDay: false  },
        { day: 'Monday', startTime: '2023-06-05T10:00:00+00:00',
          endTime: '2023-06-05T18:00:00+00:00', today: false, nextBusinessDay: false  },
        { day: 'Tuesday', startTime: '2023-06-06T10:00:00+00:00',
          endTime: '2023-06-06T20:00:00+00:00', today: false, nextBusinessDay: false  },
        { day: 'Wednesday', startTime: '2023-06-07T10:00:00+00:00',
          endTime: '2023-06-07T20:00:00+00:00', today: false, nextBusinessDay: false  }
      ]
    end
  end
end
