require 'webmock/rspec'
require_relative '../lib/locations_api'

describe LocationsApi do
  before(:each) do
    @test_locations_api = LocationsApi.new
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
      today = DateTime.new(2023, 6, 1, 9, 0)
      hours_per_day = [
        { day: 0, all_day: false, starthours: 1300, endhours: 1700, comment: '' },
        { day: 1, all_day: false, starthours: 1000, endhours: 1800, comment: '' },
        { day: 2, all_day: false, starthours: 1000, endhours: 2000, comment: '' },
        { day: 3, all_day: false, starthours: 1000, endhours: 2000, comment: '' },
        { day: 4, all_day: false, starthours: 1000, endhours: 1800, comment: '' },
        { day: 5, all_day: false, starthours: 1000, endhours: 1800, comment: '' },
        { day: 6, all_day: false, starthours: 1000, endhours: 1800, comment: '' }
      ]
      hours_array = @test_locations_api.build_hours_array(hours_per_day, today)
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

  describe 'get_location_data' do
    before do
      time = DateTime.new(2023, 6, 1, 9, 0)
      allow(DateTime).to receive(:now).and_return(time)
    end
    it 'should populate location slug, hours and address' do
      stub_request(:get, 'https://drupal.nypl.org/jsonapi/node/library?jsonapi_include=1&filter%5Bfield_ts_location_code%5D=ma')
        .to_return(status: 200, body: File.read('spec/fixtures/location_api.json'))
      locations_data = @test_locations_api.get_location_data('ma')
      expect(locations_data[:address]).to eq({ line1: 'Fifth Avenue and 42nd Street', city: 'New York', state: 'NY', postalCode: '10018' })
      expect(locations_data[:slug]).to eq('schwarzman')
      expect(locations_data[:hours]).to eq([
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
    end
  end
end
