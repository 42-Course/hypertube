require "swagger_helper"

RSpec.describe "Comments API", type: :request do
  let(:user)  { create(:user) }
  let(:movie) { create(:movie) }
  let(:token) { create(:doorkeeper_access_token, resource_owner_id: user.id) }
  let(:Authorization) { "Bearer #{token.token}" }

  path "/api/v1/comments" do
    get "List latest comments" do
      tags     "Comments"
      security [ { oauth2: [] } ]
      produces "application/json"
      parameter name: :page,     in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false,
                                 description: "1-100 (default 20)"

      response "200", "returns paginated comments" do
        before { create(:comment, user: user, movie: movie) }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["comments"]).to be_an(Array)
          expect(data["page"]).to eq(1)
          expect(data["per_page"]).to eq(20)
          expect(data["total"]).to eq(1)
        end
      end
    end

    post "Post a comment (movie_id in body)" do
      tags        "Comments"
      security    [ { oauth2: [] } ]
      consumes    "application/json"
      produces    "application/json"
      description "Alternative to POST /movies/:movie_id/comments. " \
                  "The movie_id is supplied in the payload; the rest is filled by the server."
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[comment],
        properties: {
          comment: {
            type: :object,
            required: %w[content movie_id],
            properties: {
              content:  { type: :string, example: "Great movie!" },
              movie_id: { type: :integer, example: 1 }
            }
          }
        }
      }

      response "201", "comment created" do
        let(:body) { { comment: { content: "Loved it!", movie_id: movie.id } } }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["content"]).to eq("Loved it!")
          expect(data["movie_id"]).to eq(movie.id)
        end
      end

      response "422", "invalid content" do
        let(:body) { { comment: { content: "", movie_id: movie.id } } }
        run_test!
      end
    end
  end

  path "/api/v1/movies/{movie_id}/comments" do
    parameter name: :movie_id, in: :path, type: :integer

    get "List comments for a movie" do
      tags     "Comments"
      security [ { oauth2: [] } ]
      produces "application/json"
      parameter name: :page,     in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false,
                                 description: "1-100 (default 20)"

      response "200", "returns the movie's comments only" do
        let(:movie_id) { movie.id }
        let(:other_movie) { create(:movie) }
        before do
          create(:comment, user: user, movie: movie, content: "On this movie")
          create(:comment, user: user, movie: other_movie, content: "On another")
        end
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["total"]).to eq(1)
          expect(data["comments"].size).to eq(1)
          expect(data["comments"].first["content"]).to eq("On this movie")
        end
      end
    end

    post "Post a comment on a movie" do
      tags        "Comments"
      security    [ { oauth2: [] } ]
      consumes    "application/json"
      produces    "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: [ "comment" ],
        properties: {
          comment: {
            type: :object,
            required: [ "content" ],
            properties: {
              content: { type: :string, example: "Great movie!" }
            }
          }
        }
      }

      response "201", "comment created" do
        let(:movie_id) { movie.id }
        let(:body)     { { comment: { content: "Amazing film!" } } }
        run_test!
      end

      response "422", "invalid content" do
        let(:movie_id) { movie.id }
        let(:body)     { { comment: { content: "" } } }
        run_test!
      end
    end
  end

  path "/api/v1/comments/{id}" do
    parameter name: :id, in: :path, type: :integer

    let(:comment) { create(:comment, user: user, movie: movie) }

    get "Get a comment" do
      tags     "Comments"
      security [ { oauth2: [] } ]
      produces "application/json"

      response "200", "returns comment" do
        let(:id) { comment.id }
        run_test!
      end

      response "404", "comment not found" do
        let(:id) { 0 }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to eq("Comment not found")
        end
      end
    end

    patch "Update a comment" do
      tags     "Comments"
      security [ { oauth2: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          comment: {
            type: :object,
            properties: { content: { type: :string } }
          }
        }
      }

      response "200", "comment updated" do
        let(:id)   { comment.id }
        let(:body) { { comment: { content: "Updated!" } } }
        run_test!
      end

      response "403", "cannot edit another user's comment" do
        let(:other_comment) { create(:comment, movie: movie) }
        let(:id)            { other_comment.id }
        let(:body)          { { comment: { content: "hacked" } } }
        run_test!
      end

      response "422", "invalid update" do
        let(:id)   { comment.id }
        let(:body) { { comment: { content: "x" * 1001 } } } # exceeds max length
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("errors")
        end
      end
    end

    delete "Delete a comment" do
      tags     "Comments"
      security [ { oauth2: [] } ]

      response "204", "comment deleted" do
        let(:id) { comment.id }
        run_test!
      end

      response "403", "cannot delete another user's comment" do
        let(:other_comment) { create(:comment, movie: movie) }
        let(:id)            { other_comment.id }
        run_test!
      end
    end
  end
end
