Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      post "auth/signup", to: "auth#signup"
      post "auth/login", to: "auth#login"
      delete "auth/logout", to: "auth#logout"
      get "me", to: "me#show"
      get "property_types", to: "property_types#index"
      get "properties", to: "properties#index"
      # format: false, or "/properties/12.0" would route as id 12, format "0".
      get "properties/:id", to: "properties#show", format: false
      get "watchlist", to: "watchlist#index"
      # format: false, or "/watchlist/12.0" would route as id 12, format "0".
      put "watchlist/:property_id", to: "watchlist#update", format: false
      delete "watchlist/:property_id", to: "watchlist#destroy", format: false
    end
  end
end
