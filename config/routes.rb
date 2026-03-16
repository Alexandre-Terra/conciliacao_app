Rails.application.routes.draw do
  get  "up" => "rails/health#show", as: :rails_health_check

  root "conciliacoes#new"
  post "/upload",    to: "conciliacoes#upload",    as: :upload
  get  "/configurar", to: "conciliacoes#configurar", as: :configurar
  post "/processar", to: "conciliacoes#processar",  as: :processar
  get  "/download/:uuid/:tipo", to: "conciliacoes#download", as: :download
  get  "/privacidade",          to: "conciliacoes#privacidade", as: :privacidade
end
