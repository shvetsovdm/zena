ActionController::Routing::Routes.draw do |map|
  
  map.home       ':prefix',  :controller => 'nodes',    :action => 'index',  :prefix => /[a-zA-Z]{0,2}/
  map.not_found  ':prefix/404.html',  :controller => 'nodes',    :action => 'not_found', :prefix => /\w\w/
  map.login      'login',  :controller => 'session',  :action => 'new',    :requirements => { :method => :get  }
  map.logout     'logout',  :controller => 'session',  :action => 'destroy'
  
  map.resource  :session   # singleton resource
  map.resources :users, :member => { :preferences => :get, :swap_dev => :get }
  map.resources :groups
  map.resources :iformats
  
  map.connect ':prefix/*path',  :controller => 'nodes', :action => 'show', :prefix => /\w\w/
  map.connect 'dav/*path_info', :controller => 'nodes', :action => 'webdav'
  
  map.connect 'nodes/:node_id/versions/:id.:format', :controller => 'versions', :action => 'show' #, :requirements => { :method => :get }
  
  map.resources :nodes,
    :collection => { :asearch => :get, :search => :get, :attribute => :get },
    :member =>     { :import => :post, :export => :get, :save_text => :put,
                     :order => :any, :clear_order => :any,
                     :zafu => :get, :drop => :put } do |nodes|
    nodes.resources :versions, 
                    :name_prefix => nil,
                    :member => { :edit    => :get,
                                 :propose => :put,
                                 :publish => :put,
                                 :unpublish => :put,
                                 :refuse  => :put,
                                 :remove  => :put,
                                 :redit   => :put,
                                 :preview => :put,
                                 :link    => :any,
                                 :destroy_version => :put } # FIXME: should be a DELETE
    
    nodes.resources :links
    
    #nodes.resources :discussions, :name_prefix => nil do |discussions|
    #  #discussions.resources :comments,
    #  #              :name_prefix => nil,
    #  #              :member => { :reply_to => :post }
    #end
    
  end
  
  # FIXME: merge 'documents' controller into 'nodes' (keep module for clarity)
  map.resources :documents, :collection => { :upload    => :post, :upload_progress => :post }, 
                            :member     => { :crop_form => :get,  :file_form       => :get  }
  
  map.resources :relations
  map.resources :virtual_classes
  map.resources :sites,
    :member => { :clear_cache => :post}
  map.resources :comments,
                :collection => { :empty_bin => :delete },
                :member => { :remove  => :put,
                             :publish => :put,
                             :reply_to => :post,
                           }
  map.resources :data_entries, :member => { :zafu => :get }

  # FIXME monolingual
  
  #map.login  'login' , :controller=>'login', :action=>'login'
  #map.logout 'logout', :controller=>'login', :action=>'logout'
  #
  #map.not_found '404', :controller=>'main', :action=>'not_found'
  #
  #map.user_home "#{AUTHENTICATED_PREFIX}/home", :controller=>'user', :action=>'home', :prefix=>"#{AUTHENTICATED_PREFIX}"
  #
  #map.connect ':prefix', :controller => "main", :action=>'index', :prefix=>/^(#{AUTHENTICATED_PREFIX}|\w\w)$/
  #
  #map.connect 'data/:ext/:version_id/:filename', :controller=>'document', :action=>'data'
  #
  #map.search 'z/search', :controller=>'search', :action=>'find'
  #
  #if ZENA_ENV[:monolingual]
  #  map.connect '', :controller => "main", :action=>'index'
  #  map.default 'z/:controller/:action/:id'
  #  map.site_tree ':prefix/site_tree/:id', :controller=>'main', :action=>'site_tree', :prefix=>"#{AUTHENTICATED_PREFIX}"
  #  map.connect ":prefix/*path", :controller=>'main', :action=>'show', :prefix=>"#{AUTHENTICATED_PREFIX}"
  #  map.default 'z/:controller/:action/:id'
  #  map.site_tree 'site_tree/:id', :controller=>'main', :action=>'site_tree', :prefix=>''
  #  map.connect '*path', :controller=>'main', :action=>'show', :prefix=>''  
  #else
  #  map.site_tree ':prefix/site_tree/:id', :controller=>'main', :action=>'site_tree', :prefix=>/^(#{AUTHENTICATED_PREFIX}|\w\w)$/
  #  map.connect ':prefix/*path', :controller=>'main', :action=>'show', :prefix=>/^(#{AUTHENTICATED_PREFIX}|\w\w)$/
  #  map.default 'z/:controller/:action/:id'
  #  map.connect '*path', :controller=>'main', :action=>'show'
  #end
  ## 
  ## # Allow downloading Web Service WSDL as a file with an extension
  ## # instead of a file named 'wsdl'
  ## map.connect ':controller/service.wsdl', :action => 'wsdl'
  ## 
  ## # Install the default route as the lowest priority.
  
  # map.connect ':controller/:action/:id'
  
  # temporary routes...
  map.connect 'discussions/:action/:id', :controller => 'discussions'
  map.connect 'z/link/:action/:id', :controller => 'link'
  map.connect 'z/link/:action', :controller => 'link'
  map.redirect '/redirect', :controller => 'main', :action => 'redirect'
  
  # catch all
  map.connect '*path',  :controller => 'nodes',    :action => 'catch_all'
end
=begin
ActionController::Routing::Routes.draw do |map|
  map.resources :relations

  map.resources :links

  # Add your own custom routes here.
  # The priority is based upon order of creation: first created -> highest priority.
  
  # Here's a sample route:
  # map.connect 'products/:id', :controller => 'catalog', :action => 'view'
  # Keep in mind you can assign values other than :controller and :action

  # You can have the root of your site routed by hooking up '' 
  # -- just remember to delete public/index.html.
  
end
=end