class MeetingsController < ApplicationController
  unloadable

  before_filter :find_project, :only => [:index, :new, :create]
  before_filter :find_meeting, :except => [:index, :new, :create]
  before_filter :convert_params, :only => [:create, :update]
  before_filter :authorize

  helper :journals
  helper :watchers
  helper :meeting_contents
  include WatchersHelper
  include PaginationHelper

  menu_item :new_meeting, :only => [:new, :create]

  def index
    scope = @project.meetings

    # from params => today's page otherwise => first page as fallback
    tomorrows_meetings_count = scope.from_tomorrow.count
    @page_of_today = 1 + tomorrows_meetings_count / per_page_param

    page = params['page'] ?
             page_param :
             @page_of_today

    @meetings = scope.with_users_by_date
                     .page(page)
                     .per_page(per_page_param)

    @meetings_by_start_year_month_date = Meeting.group_by_time(@meetings)
  end

  def show
    params[:tab] ||= "minutes" if @meeting.agenda.present? && @meeting.agenda.locked?
  end

  def create
    @meeting.participants.clear # Start with a clean set of participants
    @meeting.participants_attributes = params[:meeting].delete(:participants_attributes)
    @meeting.attributes = params[:meeting]
    if params[:copied_from_meeting_id].present? && params[:copied_meeting_agenda_text].present?
      @meeting.agenda = MeetingAgenda.new(
        :text => params[:copied_meeting_agenda_text],
        :comment => "Copied from Meeting ##{params[:copied_from_meeting_id]}")
      @meeting.agenda.author = User.current
    end
    if @meeting.save
      text = l(:notice_successful_create)
      link = l(:notice_timezone_missing)
      if User.current.pref.time_zone == ""
        text += " #{view_context.link_to(link, {:controller => :my, :action => :account},:class => "link_to_profile")}"
      end
      flash[:notice] = text.html_safe

      redirect_to :action => 'show', :id => @meeting
    else
      render :action => 'new', :project_id => @project
    end
  end

  def new
  end

  def copy
    params[:copied_from_meeting_id] = @meeting.id
    params[:copied_meeting_agenda_text] = @meeting.agenda.text if @meeting.agenda.present?
    @meeting = @meeting.copy(:author => User.current)
    render :action => 'new', :project_id => @project
  end

  def destroy
    @meeting.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to :action => 'index', :project_id => @project
  end

  def edit
  end

  def update
    @meeting.participants_attributes = params[:meeting].delete(:participants_attributes)
    @meeting.attributes = params[:meeting]
    if @meeting.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to :action => 'show', :id => @meeting
    else
      render :action => 'edit'
    end
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
    @meeting = Meeting.new
    @meeting.project = @project
    @meeting.author = User.current
  end

  def find_meeting
    @meeting = Meeting.find(params[:id], :include => [:project, :author, {:participants => :user}, :agenda, :minutes])
    @project = @meeting.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def convert_params
    start_date, start_time_4i, start_time_5i = params[:meeting].delete(:start_date), params[:meeting].delete(:"start_time(4i)").to_i, params[:meeting].delete(:"start_time(5i)").to_i
    begin
      zone = (User.current.time_zone.nil?) ? Time.now.localtime : User.current.time_zone
      time = Date.parse(start_date) + start_time_4i.hours + start_time_5i.minutes
      time = time - zone.utc_offset
      params[:meeting][:start_time] = time
    rescue ArgumentError
      params[:meeting][:start_time] = nil
    end
    params[:meeting][:duration] = params[:meeting][:duration].to_hours
    # Force defaults on participants
    params[:meeting][:participants_attributes] ||= {}
    params[:meeting][:participants_attributes].each {|p| p.reverse_merge! :attended => false, :invited => false}
  end
end
