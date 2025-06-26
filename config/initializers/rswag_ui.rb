# frozen_string_literal: true

# Rswag::Ui initializer
# Configuration for Swagger UI interface
Rswag::Ui.configure do |c|
  # List the Swagger endpoints that you want to be documented through the swagger-ui
  # The first parameter is the path (absolute or relative to the UI host) to the corresponding
  # endpoint and the second is a title that will be displayed in the document selector
  # NOTE: If you're using rspec-api to expose Swagger files (under swagger_root) as JSON or YAML endpoints,
  # then the list below should correspond to the relative paths for those endpoints

  c.openapi_endpoint '/api-docs/v1/swagger.yaml', 'StockRx API V1 Docs'
  
  # Add any additional swagger endpoints
  # c.swagger_endpoint '/api-docs/v2/swagger.yaml', 'API V2 Docs' # Future version

  # List additional CSS files to load within the swagger-ui iframe
  # c.additional_css_files = []
  
  # List additional JavaScript files to load within the swagger-ui iframe
  # c.additional_js_files = []
  
  # Configure custom headers
  c.config_object = {
    # Use the validatorUrl to enable/disable online schema validation
    validatorUrl: nil,
    
    # Display options
    docExpansion: 'list', # 'none', 'list', or 'full'
    defaultModelsExpandDepth: 1,
    defaultModelExpandDepth: 1,
    
    # Feature toggles
    tryItOutEnabled: true,
    requestSnippetsEnabled: true,
    deepLinking: true,
    displayRequestDuration: true,
    
    # Request timeout (in milliseconds)
    requestTimeout: 30000,
    
    # Persist authorization data
    persistAuthorization: true
  }
end