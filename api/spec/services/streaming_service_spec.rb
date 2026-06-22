require "rails_helper"

RSpec.describe StreamingService, type: :service do
  let(:base)   { "http://streaming.test" }
  let(:magnet) { "magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01" }
  let(:media_id) { "0123456789abcdef0123456789abcdef" }

  around do |example|
    previous = {
      "STREAM_TICKET_SECRET"           => ENV["STREAM_TICKET_SECRET"],
      "STREAMING_SERVICE_INTERNAL_URL" => ENV["STREAMING_SERVICE_INTERNAL_URL"],
      "STREAMING_SERVICE_URL"          => ENV["STREAMING_SERVICE_URL"]
    }
    ENV["STREAM_TICKET_SECRET"]           = "test-stream-ticket-secret"
    ENV["STREAMING_SERVICE_INTERNAL_URL"] = base
    ENV["STREAMING_SERVICE_URL"]          = "http://localhost:4567"
    example.run
    previous.each { |key, value| ENV[key] = value }
  end

  it "creates the media and returns its media_id, forwarding the magnet" do
    stub = stub_request(:post, "#{base}/media")
      .with(headers: { "Content-Type" => "application/json" }) do |req|
        JSON.parse(req.body)["magnet"] == magnet &&
          req.headers["Authorization"].to_s.start_with?("Bearer ")
      end
      .to_return(status: 201, body: { media_id: media_id }.to_json,
                 headers: { "Content-Type" => "application/json" })

    expect(described_class.new.ensure_media(magnet: magnet)).to eq(media_id)
    expect(stub).to have_been_requested
  end

  it "authenticates with a valid service-scoped token the streaming side accepts" do
    captured = nil
    stub_request(:post, "#{base}/media").to_return do |req|
      captured = req.headers["Authorization"].to_s.delete_prefix("Bearer ")
      { status: 201, body: { media_id: media_id }.to_json }
    end

    described_class.new.ensure_media(magnet: magnet)

    claims, = JWT.decode(captured, ENV["STREAM_TICKET_SECRET"], true,
                         algorithm: "HS256", aud: "hypertube-streaming", verify_aud: true)
    expect(claims["scope"]).to eq("service")
    expect(claims["iss"]).to eq("hypertube-api")
  end

  it "raises on a non-success response" do
    stub_request(:post, "#{base}/media").to_return(status: 503)
    expect { described_class.new.ensure_media(magnet: magnet) }
      .to raise_error(StreamingService::Error)
  end

  it "raises when the response carries no media_id" do
    stub_request(:post, "#{base}/media").to_return(status: 201, body: "{}")
    expect { described_class.new.ensure_media(magnet: magnet) }
      .to raise_error(StreamingService::Error)
  end

  it "raises when the streaming service URL is not configured" do
    ENV["STREAMING_SERVICE_INTERNAL_URL"] = nil
    ENV["STREAMING_SERVICE_URL"]          = nil
    expect { described_class.new.ensure_media(magnet: magnet) }
      .to raise_error(StreamingService::Error, /not configured/)
  end
end
