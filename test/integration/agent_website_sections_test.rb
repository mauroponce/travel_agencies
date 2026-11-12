require "test_helper"
require_relative "../support_agent_data"

class AgentWebsiteSectionsTest < ActionDispatch::IntegrationTest
  include AgentTestData

  test "existing sections are enabled and about is unchecked by default" do
    workspace = agent_workspace
    assert workspace.show_catalog?
    assert_not workspace.show_about?
    login_website(workspace)
    get agent_website_path
    assert_response :success
    assert_select "input[name='agent_workspace[show_about]'][type=checkbox]:not([checked])"
    assert_select "fieldset#agent-about-editor[hidden][disabled]"
    assert_select "input[name='agent_workspace[show_presentation]'], textarea[name='agent_workspace[presentation]']", count: 0
    get agent_site_path(agent_slug: workspace.slug)
    assert_response :success
    assert_select "#presentacion", count: 0
    assert_select "a.agent-floating-whatsapp[href=?][target='_blank'][rel=noopener][aria-label='Consultar por WhatsApp']", "https://wa.me/#{workspace.whatsapp}", count: 1
    assert_select "#viajes"
    assert_select "#sobre-mi", count: 0
  end

  test "agent publishes a photo and escaped personal text in the public site and preview" do
    workspace = agent_workspace
    login_website(workspace)
    text = "Soy Lucía y te acompaño en cada viaje.\n<script>alert('hola')</script>"
    patch agent_website_path, params: { agent_workspace: { show_about: "1", about_text: text, about_photo: png_upload } }
    assert_redirected_to agent_website_path
    assert workspace.reload.show_about?
    assert_equal text, workspace.about_text
    assert workspace.about_photo.attached?
    get agent_website_path
    assert_response :success
    assert_select "#agent-about-editor:not([hidden]):not([disabled])"
    assert_select "img[src=?]", about_photo_agent_website_path
    get about_photo_agent_website_path
    assert_response :success
    assert_equal "image/png", response.media_type
    [ agent_site_path(agent_slug: workspace.slug), preview_agent_website_path ].each do |path|
      get path
      assert_response :success
      assert_select "#sobre-mi h2", text: "Sobre mí"
      assert_select "#sobre-mi .agent-about-text", text: text.squish
      assert_select "#sobre-mi script", count: 0
      assert_select "#sobre-mi img[src=?]", workspace.url(path: photo_path(workspace))
    end
    get photo_path(workspace)
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal File.binread(Rails.root.join("test/fixtures/files/agent.png")), response.body
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "unchecking sections hides them and their public photo while preserving content" do
    workspace = agent_workspace(show_about: true, about_text: "Mi historia personal", about_photo: png_upload)
    login_website(workspace)
    photo = photo_path(workspace)
    patch agent_website_path, params: { agent_workspace: { show_presentation: "0", show_catalog: "0", show_about: "0" } }
    assert_redirected_to agent_website_path
    assert_equal "Mi historia personal", workspace.reload.about_text
    assert workspace.about_photo.attached?
    [ agent_site_path(agent_slug: workspace.slug), preview_agent_website_path ].each do |path|
      get path
      assert_response :success
      assert_select "#presentacion, #viajes, #sobre-mi", count: 0
      assert_select "a.agent-floating-whatsapp[href=?]", "https://wa.me/#{workspace.whatsapp}", count: 1
      assert_select ".sidebar", count: 0 if path == preview_agent_website_path
      assert_not_includes response.body, "Mi historia personal"
    end
    get photo
    assert_response :not_found
    patch agent_website_path, params: { agent_workspace: { show_about: "1" } }
    assert_redirected_to agent_website_path
    get agent_site_path(agent_slug: workspace.slug)
    assert_select "#sobre-mi .agent-about-text", text: "Mi historia personal"
    get photo
    assert_response :success
  end

  test "invalid photo and oversized text do not replace saved content" do
    workspace = agent_workspace(show_about: true, about_text: "Mi historia", about_photo: png_upload)
    login_website(workspace)
    original_blob = workspace.about_photo.blob_id
    pdf = Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/agent.pdf"), "application/pdf")
    patch agent_website_path, params: { agent_workspace: { about_text: "Nuevo texto", about_photo: pdf } }
    assert_response :unprocessable_entity
    assert_select "textarea[name='agent_workspace[about_text]']", text: "Nuevo texto"
    assert_equal "Mi historia", workspace.reload.about_text
    assert_equal original_blob, workspace.about_photo.blob_id
    patch agent_website_path, params: { agent_workspace: { about_text: "a" * 1201, about_photo: png_upload } }
    assert_response :unprocessable_entity
    assert_includes response.body, "1200 caracteres"
    assert_equal "Mi historia", workspace.reload.about_text
    assert_equal original_blob, workspace.about_photo.blob_id
  end

  test "public photo is scoped to its agent and current attachment and suspended agents stay private" do
    workspace = agent_workspace(show_about: true, about_photo: png_upload)
    other = agent_workspace(show_about: true, about_photo: png_upload)
    host! PlatformHosts.platform_host
    get photo_path(workspace)
    assert_response :success
    get photo_path(workspace, blob_id: other.about_photo.blob_id)
    assert_response :not_found
    get about_photo_agent_website_path
    assert_redirected_to root_path
    login_agent(other)
    host! workspace.hostname
    patch agent_website_path, params: { agent_workspace: { show_about: "0", about_text: "Intrusión" } }
    assert_response :redirect
    assert workspace.reload.show_about?
    assert_nil workspace.about_text
    host! PlatformHosts.platform_host
    stale_photo = photo_path(workspace)
    workspace.update!(about_photo: png_upload)
    get stale_photo
    assert_response :not_found
    workspace.update!(status: "suspended")
    get photo_path(workspace)
    assert_response :not_found
  end

  private

  def login_website(workspace)
    host! PlatformHosts.platform_host
    get "/test/sign-in", params: { email: workspace.owner.email }
  end

  def photo_path(workspace, blob_id: workspace.about_photo.blob_id)
    agent_site_about_photo_path(agent_slug: workspace.slug, blob_id:)
  end
end
