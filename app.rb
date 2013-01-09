require "restclient"
require "json"
require "cuba"
require "cuba/render"
require "rack/flash"
require "geocoder"

BadWeather = Class.new(RuntimeError)

class ZipWeather

  UNKNOWN = "Unknown"

  attr_reader :zipcode, :api_key

  def initialize(zipcode, api_key)
    @zipcode = zipcode
    @api_key = api_key
  end

  def conditions
    current_observation(:weather) || unknown
  end

  def location
    (current_observation(:display_location) || {}).fetch("full", unknown)
  end

  def temp_f
    if current_observation(:temp_f)
      "#{current_observation(:temp_f)} F"
    else
      unknown
    end
  end

  def current_observation(key)
    (data["current_observation"] || {})[key.to_s]
  end

  def error
    fetch_data
    @error
  end

  def valid?
    ! error?
  end

  def error?
    !! error
  end

  private

  def unknown
    UNKNOWN
  end

  def data
    @data ||= begin
      data = JSON[raw_data]
      check_error(data)
      data
    end
  end
  alias_method :fetch_data, :data

  def raw_data
    RestClient.get endpoint_url
  end

  def check_error(data)
    if data["response"]["error"]
      @error = data["response"]["error"]["description"]
    end
  end

  def endpoint_url
    "http://api.wunderground.com/api/#{api_key}/conditions/q/#{zipcode}.json"
  end
end

Cuba.use Rack::Session::Cookie
Cuba.use Rack::Flash

class FakeIp
  def initialize(app, fake_ip)
    @app = app
    @fake_ip = fake_ip
  end

  def call(env)
    env["REMOTE_ADDR"] = @fake_ip
    @app.call(env)
  end
end
Cuba.use FakeIp, ENV.fetch("FAKE_IP")

Cuba.settings[:weather_api_key] = ENV.fetch("WEATHER_API_KEY")

Cuba.plugin Rack::Utils
Cuba.plugin Cuba::Render

Cuba.define do
  def h(*args)
    escape_html(*args)
  end

  def flash
    env['x-rack.flash']
  end

  def postal_code
    req.location.postal_code
  end

  def zip_weather
    @zip_weather ||= ZipWeather.new req.params['zipcode'], settings[:weather_api_key]
  end

  on get, "lookup" do
    on param("zipcode"), zip_weather.valid? do
      res.write view("weather")
    end

    on param("zipcode"), zip_weather.error? do
      flash[:error] = zip_weather.error
      res.redirect "/"
    end

    on default do
      flash[:error] = "You must provide a zipcode"
      res.redirect "/"
    end
  end

  on default do
    res.write view("index")
  end
end
