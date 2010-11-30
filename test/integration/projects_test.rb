require "integration_test_helper"

class ProjectsTest < ActionController::IntegrationTest
  def setup
    super
    `cd test/files; mkdir repo; cd repo; git init; echo "my file" > file; git add file; git commit -m "my file added"`
  end

  def teardown
    FileUtils.rm_rf("test/files/repo")
    FileUtils.rm_rf("builds/*")
    super
  end

  test "user can add a project" do
    visit "/"
    click_link "New project"
    fill_in "Name", :with => "My shiny project"
    fill_in "Steps", :with => "ls -al ."
    select "Git", :from => "Vcs type"
    fill_in "Vcs source", :with => "test/files/repo"
    fill_in "Vcs branch", :with => "master"
    fill_in "Max builds", :with => "3"
    fill_in "Hook name", :with => "myshinyproject"
    assert_difference("Project.count", +1) do
      click_button "Create"
    end
  end

  test "one can successfully build a project" do
    project = Project.make(:steps => "ls -al file", :name => "Valid", :vcs_source => "test/files/repo", :vcs_type => "git")
    visit "/"
    click_link_or_button "Valid"
    assert_difference("Delayed::Job.count", +1) do
      click_link_or_button "Build now"
    end
    job = Delayed::Job.order("created_at DESC").first
    job.invoke_job
    visit "/"
    assert page.has_css?("#project_#{project.id}.#{Build::STATUS_OK}")
  end

  test "project build can fail" do
    project = Project.make(:steps => "ls -al file_doesnt_exist", :name => "Invalid", :vcs_source => "test/files/repo", :vcs_type => "git")
    visit "/"
    click_link_or_button "Invalid"
    assert_difference("Delayed::Job.count", +1) do
      click_link_or_button "Build now"
    end
    job = Delayed::Job.order("created_at DESC").first
    job.invoke_job
    visit "/"
    assert page.has_css?("#project_#{project.id}.#{Build::STATUS_FAILED}")
  end

  test "removing projects from list" do
    project = Project.make(:steps => "ls -al file", :name => "Valid", :vcs_source => "test/files/repo", :vcs_type => "git")
    visit "/"
    click_link_or_button "Valid"
    click_link "Remove project"
    assert_difference("Project.count", -1) do
      click_button "Yes, I'm sure"
    end
  end

  test "user can reorder projects on project list" do
    project1 = Project.make(:steps => "echo 'ha'", :name => "Valid", :vcs_source => "test/files/repo", :vcs_type => "git")
    project2 = Project.make(:steps => "echo 'sa'", :name => "Valid2", :vcs_source => "test/files/repo", :vcs_type => "git")
    visit "/"
    within("#project_#{project2.id} .updown") do
      assert page.has_xpath?("a[contains(@href, 'up=')]")
      assert ! page.has_xpath?("a[contains(@href, 'down=')]")
    end
    within("#project_#{project1.id} .updown") do
      assert page.has_xpath?("a[contains(@href, 'down')]")
      assert ! page.has_xpath?("a[contains(@href, 'up')]")
    end
    click_link "↓"
    within("#project_#{project1.id} .updown") do
      assert page.has_xpath?("a[contains(@href, 'up=')]")
      assert ! page.has_xpath?("a[contains(@href, 'down=')]")
    end
    within("#project_#{project2.id} .updown") do
      assert page.has_xpath?("a[contains(@href, 'down')]")
      assert ! page.has_xpath?("a[contains(@href, 'up')]")
    end
  end

  test "project with invalid repo shows appropriate errors" do
    project = Project.make(:steps => "echo 'ha'", :name => "Valid", :vcs_source => "no/such/repo", :vcs_type => "git")
    visit "/"
    click_link "Valid"
    assert_difference("Build.count", +1) do
      click_link "Build now"
    end
    build = project.recent_build
    job = Delayed::Job.order("created_at DESC").first
    job.invoke_job
    click_link build.display_name
    assert page.has_content?("Could not switch to 'no/such'")
  end

  test "project should have a link to the atom feed" do
    project = Project.make(:steps => "echo 'ha'", :name => "Atom project", :vcs_source => "no/such/repo", :vcs_type => "git")
    visit "/projects/#{[project.id, project.name.to_url].join("-")}"
    assert page.has_link?("Feed")
  end

  test "project should have an atom feed" do
    project = Project.make(:steps => "echo 'ha'", :name => "Atom project 2", :vcs_source => "no/such/repo", :vcs_type => "git")
    build_1 = Build.make(:project => project, :created_at => 2.weeks.ago)
    build_2 = Build.make(:project => project, :created_at => 1.week.ago)
    visit "/projects/#{[project.id, project.name.to_url].join("-")}/feed.atom"
    parsed = Crack::XML.parse(page.body)
    assert_equal "Atom project 2 CI", parsed["feed"]["title"]
    assert_equal 2, parsed["feed"]["entry"].size
    assert_equal "#{build_1.display_name} - #{build_1.status == Build::STATUS_OK ? "SUCCESS" : "FAILED"}", parsed["feed"]["entry"][0]["title"]
    assert_equal "#{build_2.display_name} - #{build_2.status == Build::STATUS_OK ? "SUCCESS" : "FAILED"}", parsed["feed"]["entry"][1]["title"]
  end
end
