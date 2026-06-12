require "swagger_helper"

RSpec.describe "Comments API", type: :request do
  let(:user)  { create(:user) }
  let(:movie) { create(:movie) }
  let(:token) { create(:doorkeeper_access_token, resource_owner_id: user.id) }
  let(:Authorization) { "Bearer #{token.token}" }

  path "/api/v1/comments" do
    get "List latest comments" do
      tags     "Comments"
      security [{ oauth2: [] }]
      produces "application/json"

      response "200", "returns comments" do
        before { create(:comment, user: user, movie: movie) }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to be_an(Array)
        end
      end
    end
  end

  path "/api/v1/movies/{movie_id}/comments" do
    parameter name: :movie_id, in: :path, type: :integer

    post "Post a comment on a movie" do
      tags        "Comments"
      security    [{ oauth2: [] }]
      consumes    "application/json"
      produces    "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: ["comment"],
        properties: {
          comment: {
            type: :object,
            required: ["content"],
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
      security [{ oauth2: [] }]
      produces "application/json"

      response "200", "returns comment" do
        let(:id) { comment.id }
        run_test!
      end
    end

    patch "Update a comment" do
      tags     "Comments"
      security [{ oauth2: [] }]
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
    end

    delete "Delete a comment" do
      tags     "Comments"
      security [{ oauth2: [] }]

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
