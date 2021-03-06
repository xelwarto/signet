# Copyright (C) 2010 Google Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

require 'base64'
require 'signet'
require 'multi_json'
require 'compat/multi_json'
require 'signet/ssl_config'

module Signet #:nodoc:
  ##
  # An implementation of http://tools.ietf.org/html/draft-ietf-oauth-v2-10
  #
  # This module will be updated periodically to support newer drafts of the
  # specification, as they become widely deployed.
  module OAuth2
    def self.parse_authorization_header(field_value)
      auth_scheme = field_value[/^([-._0-9a-zA-Z]+)/, 1]
      case auth_scheme
      when /^Basic$/i
        # HTTP Basic is allowed in OAuth 2
        return self.parse_basic_credentials(field_value[/^Basic\s+(.*)$/i, 1])
      when /^OAuth$/i
        # Other token types may be supported eventually
        return self.parse_bearer_credentials(field_value[/^OAuth\s+(.*)$/i, 1])
      else
        raise ParseError,
          'Parsing non-OAuth Authorization headers is out of scope.'
      end
    end

    def self.parse_www_authenticate_header(field_value)
      auth_scheme = field_value[/^([-._0-9a-zA-Z]+)/, 1]
      case auth_scheme
      when /^OAuth$/i
        # Other token types may be supported eventually
        return self.parse_oauth_challenge(field_value[/^OAuth\s+(.*)$/i, 1])
      else
        raise ParseError,
          'Parsing non-OAuth WWW-Authenticate headers is out of scope.'
      end
    end

    def self.parse_basic_credentials(credential_string)
      decoded = Base64.decode64(credential_string)
      client_id, client_secret = decoded.split(':', 2)
      return [['client_id', client_id], ['client_secret', client_secret]]
    end

    def self.parse_bearer_credentials(credential_string)
      access_token = credential_string[/^([^,\s]+)(?:\s|,|$)/i, 1]
      parameters = []
      parameters << ['access_token', access_token]
      auth_param_string = credential_string[/^(?:[^,\s]+)\s*,\s*(.*)$/i, 1]
      if auth_param_string
        # This code will rarely get called, but is included for completeness
        parameters.concat(Signet.parse_auth_param_list(auth_param_string))
      end
      return parameters
    end

    def self.parse_oauth_challenge(challenge_string)
      return Signet.parse_auth_param_list(challenge_string)
    end

    def self.parse_credentials(body, content_type)
      if !body.kind_of?(String)
        raise TypeError, "Expected String, got #{body.class}."
      end
      case content_type
      when /^application\/json.*/
        return MultiJson.load(body)
      when /^application\/x-www-form-urlencoded.*/
        return Hash[Addressable::URI.form_unencode(body)]
      else
        raise ArgumentError, "Invalid content type '#{content_type}'"
      end
    end

    ##
    # Generates a Basic Authorization header from a client identifier and a
    # client password.
    #
    # @param [String] client_id
    #   The client identifier.
    # @param [String] client_password
    #   The client password.
    #
    # @return [String]
    #   The value for the HTTP Basic Authorization header.
    def self.generate_basic_authorization_header(client_id, client_password)
      if client_id =~ /:/
        raise ArgumentError,
          "A client identifier may not contain a ':' character."
      end
      return 'Basic ' + Base64.encode64(
        client_id + ':' + client_password
      ).gsub(/\n/, '')
    end

    ##
    # Generates an authorization header for an access token
    #
    # @param [String] access_token
    #   The access token.
    # @param [Hash] auth_params
    #   Additonal parameters to be encoded in the header
    #
    # @return [String]
    #   The value for the HTTP Basic Authorization header.
    def self.generate_bearer_authorization_header(
        access_token, auth_params=nil)
      # TODO: escaping?
      header = "Bearer #{access_token}"
      if auth_params && !auth_params.empty?
        header += (", " +
          (auth_params.inject([]) do |accu, (key, value)|
            accu << "#{key}=\"#{value}\""
            accu
          end).join(", ")
        )
      end
      return header
    end

    ##
    # Appends the necessary OAuth parameters to
    # the base authorization endpoint URI.
    #
    # @param [Addressable::URI, String, #to_str] authorization_uri
    #   The base authorization endpoint URI.
    #
    # @return [String] The authorization URI to redirect the user to.
    def self.generate_authorization_uri(authorization_uri, parameters={})
      for key, value in parameters
        parameters.delete(key) if value == nil
      end
      parsed_uri = Addressable::URI.parse(authorization_uri).dup
      query_values = parsed_uri.query_values || {}
      query_values.keys.each do |key|
        query_values[(key.to_sym rescue key) || key] = query_values.delete(key)
      end
      query_values = query_values.merge(parameters)
      parsed_uri.query_values = query_values
      return parsed_uri.normalize.to_s
    end
  end
end
