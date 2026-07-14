Pod::Spec.new do |s|
  s.name                  = 'SignalSDK'
  s.version               = '1.0.0'
  s.summary               = 'Signal iOS SDK for player analytics and marketing automation.'
  s.description           = <<-DESC
    Signal iOS SDK provides player identity management, custom event tracking,
    and automatic lifecycle events (foreground, background, session) for iOS apps.
    Mirrors the Signal Android SDK public API exactly.
  DESC

  # PLACEHOLDER — see PUBLISHING.md "One-time setup" for the real public org/repo before
  # running `pod trunk push`.
  s.homepage              = 'https://github.com/signal-sdk/ios-sdk' # TODO: real public repo URL
  s.license               = { :type => 'MIT', :file => 'LICENSE' }
  s.author                = { 'Signal' => 'support@signal-sdk.com' }
  s.source                = { :git => 'https://github.com/signal-sdk/ios-sdk.git', :tag => s.version.to_s } # TODO

  s.ios.deployment_target = '13.0'
  s.swift_versions        = ['5.9']

  s.source_files          = 'Sources/SignalSDK/**/*.swift'

  # No external dependencies — Foundation + UIKit only
end
