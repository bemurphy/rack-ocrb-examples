require "restclient"
require "json"
require "sinatra"
require "rack/flash"

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

enable :sessions
use Rack::Flash
set :weather_api_key, ENV.fetch("WEATHER_API_KEY")

helpers do
  include Rack::Utils
  alias_method :h, :escape_html

  def zip_weather
    @zip_weather ||= ZipWeather.new params[:zipcode], settings.weather_api_key
  end
end

get "/" do
  erb :index
end

get "/lookup" do
  if zip_weather.error?
    flash[:error] = zip_weather.error
    redirect "/"
  else
    erb :weather
  end
end
