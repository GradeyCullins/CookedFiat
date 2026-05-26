Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "sitemap.xml" => "sitemap#index", as: :sitemap, defaults: { format: "xml" }

  resource :calculation, only: [ :show ], controller: "calculations"

  root "calculations#index"
end
