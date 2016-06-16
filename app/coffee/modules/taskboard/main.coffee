###
# Copyright (C) 2014-2016 Andrey Antukh <niwi@niwi.nz>
# Copyright (C) 2014-2016 Jesús Espino Garcia <jespinog@gmail.com>
# Copyright (C) 2014-2016 David Barragán Merino <bameda@dbarragan.com>
# Copyright (C) 2014-2016 Alejandro Alonso <alejandro.alonso@kaleidos.net>
# Copyright (C) 2014-2016 Juan Francisco Alcántara <juanfran.alcantara@kaleidos.net>
# Copyright (C) 2014-2016 Xavi Julian <xavier.julian@kaleidos.net>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# File: modules/taskboard.coffee
###

taiga = @.taiga
toggleText = @.taiga.toggleText
mixOf = @.taiga.mixOf
groupBy = @.taiga.groupBy
bindOnce = @.taiga.bindOnce
scopeDefer = @.taiga.scopeDefer
timeout = @.taiga.timeout
bindMethods = @.taiga.bindMethods

module = angular.module("taigaTaskboard")


#############################################################################
## Taskboard Controller
#############################################################################

class TaskboardController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope",
        "$rootScope",
        "$tgRepo",
        "$tgConfirm",
        "$tgResources",
        "tgResources"
        "$routeParams",
        "$q",
        "tgAppMetaService",
        "$tgLocation",
        "$tgNavUrls"
        "$tgEvents"
        "$tgAnalytics",
        "$translate",
        "tgErrorHandlingService",
        "tgTaskboardTasks",
        "$tgStorage"
    ]

    constructor: (@scope, @rootscope, @repo, @confirm, @rs, @rs2, @params, @q, @appMetaService, @location, @navUrls,
                  @events, @analytics, @translate, @errorHandlingService, @taskboardTasksService, @storage) ->
        bindMethods(@)
        @.zoom = @storage.get("taskboard_zoom") or 0
        @scope.userstories = []

        @scope.sectionName = @translate.instant("TASKBOARD.SECTION_NAME")
        @.initializeEventHandlers()

        promise = @.loadInitialData()

        # On Success
        promise.then => @._setMeta()
        # On Error
        promise.then null, @.onInitialDataError.bind(@)

        taiga.defineImmutableProperty @.scope, "usTasks", () =>
            return @taskboardTasksService.usTasks

    _setMeta: ->
        prettyDate = @translate.instant("BACKLOG.SPRINTS.DATE")

        title = @translate.instant("TASKBOARD.PAGE_TITLE", {
            projectName: @scope.project.name
            sprintName: @scope.sprint.name
        })
        description =  @translate.instant("TASKBOARD.PAGE_DESCRIPTION", {
            projectName: @scope.project.name
            sprintName: @scope.sprint.name
            startDate: moment(@scope.sprint.estimated_start).format(prettyDate)
            endDate: moment(@scope.sprint.estimated_finish).format(prettyDate)
            completedPercentage: @scope.stats.completedPercentage or "0"
            completedPoints: @scope.stats.completedPointsSum or "--"
            totalPoints: @scope.stats.totalPointsSum or "--"
            openTasks: @scope.stats.openTasks or "--"
            totalTasks: @scope.stats.total_tasks or "--"
        })

        @appMetaService.setAll(title, description)

    initializeEventHandlers: ->
        @scope.$on "taskform:bulk:success", (event, tasks) =>
            @.refreshTagsColors().then () =>
                @taskboardTasksService.add(tasks)

            @analytics.trackEvent("task", "create", "bulk create task on taskboard", 1)

        @scope.$on "taskform:new:success", (event, task) =>
            @.refreshTagsColors().then () =>
                @taskboardTasksService.add(task)

            @analytics.trackEvent("task", "create", "create task on taskboard", 1)

        @scope.$on "taskform:edit:success", (event, task) =>
            @.refreshTagsColors().then () =>
                @taskboardTasksService.replaceModel(task)

        @scope.$on("taskboard:task:move", @.taskMove)
        @scope.$on("assigned-to:added", @.onAssignedToChanged)

    onAssignedToChanged: (ctx, userid, taskModel) ->
        taskModel.assigned_to = userid

        @taskboardTasksService.replaceModel(taskModel)

        promise = @repo.save(taskModel)
        promise.then null, ->
            console.log "FAIL" # TODO

    initializeSubscription: ->
        routingKey = "changes.project.#{@scope.projectId}.tasks"
        @events.subscribe @scope, routingKey, (message) =>
            @.loadTaskboard()

        routingKey1 = "changes.project.#{@scope.projectId}.userstories"
        @events.subscribe @scope, routingKey1, (message) =>
            @.refreshTagsColors()
            @.loadSprintStats()
            @.loadSprint()

    loadProject: ->
        return @rs.projects.get(@scope.projectId).then (project) =>
            if not project.is_backlog_activated
                @errorHandlingService.permissionDenied()

            @scope.project = project
            # Not used at this momment
            @scope.pointsList = _.sortBy(project.points, "order")
            @scope.pointsById = groupBy(project.points, (e) -> e.id)
            @scope.roleById = groupBy(project.roles, (e) -> e.id)
            @scope.taskStatusList = _.sortBy(project.task_statuses, "order")
            @scope.usStatusList = _.sortBy(project.us_statuses, "order")
            @scope.usStatusById = groupBy(project.us_statuses, (e) -> e.id)

            @scope.$emit('project:loaded', project)

            @.fillUsersAndRoles(project.members, project.roles)

            return project

    loadSprintStats: ->
        return @rs.sprints.stats(@scope.projectId, @scope.sprintId).then (stats) =>
            totalPointsSum =_.reduce(_.values(stats.total_points), ((res, n) -> res + n), 0)
            completedPointsSum = _.reduce(_.values(stats.completed_points), ((res, n) -> res + n), 0)
            remainingPointsSum = totalPointsSum - completedPointsSum
            remainingTasks = stats.total_tasks - stats.completed_tasks
            @scope.stats = stats
            @scope.stats.totalPointsSum = totalPointsSum
            @scope.stats.completedPointsSum = completedPointsSum
            @scope.stats.remainingPointsSum = remainingPointsSum
            @scope.stats.remainingTasks = remainingTasks
            if stats.totalPointsSum
                @scope.stats.completedPercentage = Math.round(100*stats.completedPointsSum/stats.totalPointsSum)
            else
                @scope.stats.completedPercentage = 0

            @scope.stats.openTasks = stats.total_tasks - stats.completed_tasks
            return stats

    refreshTagsColors: ->
        return @rs.projects.tagsColors(@scope.projectId).then (tags_colors) =>
            @scope.project.tags_colors = tags_colors

    loadSprint: ->
        return @rs.sprints.get(@scope.projectId, @scope.sprintId).then (sprint) =>
            @scope.sprint = sprint
            @scope.userstories = _.sortBy(sprint.user_stories, "sprint_order")

            @taskboardTasksService.setUserstories(@scope.userstories)

            return sprint

    loadTasks: ->
        return @rs.tasks.list(@scope.projectId, @scope.sprintId).then (tasks) =>
            @taskboardTasksService.init(@scope.project, @scope.usersById)
            @taskboardTasksService.set(tasks)

    loadTaskboard: ->
        return @q.all([
            @.refreshTagsColors(),
            @.loadSprintStats(),
            @.loadSprint().then(=> @.loadTasks())
        ])

    loadInitialData: ->
        params = {
            pslug: @params.pslug
            sslug: @params.sslug
        }

        promise = @repo.resolve(params).then (data) =>
            @scope.projectId = data.project
            @scope.sprintId = data.milestone
            @.initializeSubscription()
            return data

        return promise.then(=> @.loadProject())
                      .then(=> @.loadTaskboard())

    showPlaceHolder: (statusId, usId) ->
        if !@taskboardTasksService.tasksRaw.length
            if @scope.taskStatusList[0].id == statusId &&
              (!@scope.userstories.length || @scope.userstories[0].id == usId)
                return true

        return false

    editTask: (id) ->
        task = @.taskboardTasksService.getTask(id)

        task = task.set('loading', true)
        @taskboardTasksService.replace(task)

        @rs.tasks.getByRef(task.getIn(['model', 'project']), task.getIn(['model', 'ref'])).then (editingTask) =>
             @rs2.attachments.list("task", task.get('id'), task.getIn(['model', 'project'])).then (attachments) =>
                @rootscope.$broadcast("taskform:edit", editingTask, attachments.toJS())
                task = task.set('loading', false)
                @taskboardTasksService.replace(task)

    prepareBulkUpdateData: (uses) ->
         return _.map(uses, (x) -> {"task_id": x.id, "order": x["taskboard_order"]})

    taskMove: (ctx, task, oldStatusId, usId, statusId, order) ->
        task = @taskboardTasksService.getTaskModel(task.get('id'))

        itemsToSave = @taskboardTasksService.move(task.id, usId, statusId, order)

        # Persist the userstory
        promise = @repo.save(task)

        # Rehash userstories order field
        # and persist in bulk all changes.
        promise = promise.then =>
            @.loadSprintStats()

            itemsToSave = _.reject(itemsToSave, {"id": task.id})
            data = @.prepareBulkUpdateData(itemsToSave)

            return @rs.tasks.bulkUpdateTaskTaskboardOrder(@scope.project.id, data)

            @.refreshTasksOrder(tasks)

    ## Template actions
    addNewTask: (type, us) ->
        switch type
            when "standard" then @rootscope.$broadcast("taskform:new", @scope.sprintId, us?.id)
            when "bulk" then @rootscope.$broadcast("taskform:bulk", @scope.sprintId, us?.id)

    changeTaskAssignedTo: (id) ->
        task = @taskboardTasksService.getTaskModel(id)

        @rootscope.$broadcast("assigned-to:add", task)

module.controller("TaskboardController", TaskboardController)


#############################################################################
## TaskboardDirective
#############################################################################

TaskboardDirective = ($rootscope) ->
    link = ($scope, $el, $attrs) ->
        $ctrl = $el.controller()

        $el.on "click", ".toggle-analytics-visibility", (event) ->
            event.preventDefault()
            target = angular.element(event.currentTarget)
            target.toggleClass('active')
            $rootscope.$broadcast("taskboard:graph:toggle-visibility")

        tableBodyDom = $el.find(".taskboard-table-body")
        tableBodyDom.on "scroll", (event) ->
            target = angular.element(event.currentTarget)
            tableHeaderDom = $el.find(".taskboard-table-header .taskboard-table-inner")
            tableHeaderDom.css("left", -1 * target.scrollLeft())

        $scope.$on "$destroy", ->
            $el.off()

    return {link: link}

module.directive("tgTaskboard", ["$rootScope", TaskboardDirective])

#############################################################################
## Taskboard Squish Column Directive
#############################################################################

TaskboardSquishColumnDirective = (rs) ->
    avatarWidth = 40
    maxColumnWidth = 300

    link = ($scope, $el, $attrs) ->
        $scope.$on "sprint:task:moved", () =>
            recalculateTaskboardWidth()

        $scope.$watch "usTasks", () ->
            if $scope.project
                $scope.statusesFolded = rs.tasks.getStatusColumnModes($scope.project.id)
                $scope.usFolded = rs.tasks.getUsRowModes($scope.project.id, $scope.sprintId)

                recalculateTaskboardWidth()

        $scope.foldStatus = (status) ->
            $scope.statusesFolded[status.id] = !!!$scope.statusesFolded[status.id]
            rs.tasks.storeStatusColumnModes($scope.projectId, $scope.statusesFolded)

            recalculateTaskboardWidth()

        $scope.foldUs = (us) ->
            if !us
                $scope.usFolded[null] = !!!$scope.usFolded[null]
            else
                $scope.usFolded[us.id] = !!!$scope.usFolded[us.id]

            rs.tasks.storeUsRowModes($scope.projectId, $scope.sprintId, $scope.usFolded)

            recalculateTaskboardWidth()

        getCeilWidth = (usId, statusId) =>
            if usId
                tasks = $scope.usTasks.getIn([usId.toString(), statusId.toString()]).size
            else
                tasks = $scope.usTasks.getIn(['null', statusId.toString()]).size

            if $scope.statusesFolded[statusId]
                if tasks and $scope.usFolded[usId]
                    tasksMatrixSize = Math.round(Math.sqrt(tasks))
                    width = avatarWidth * tasksMatrixSize
                else
                    width = avatarWidth

                return width

            return 0

        setStatusColumnWidth = (statusId, width) =>
            column = $el.find(".squish-status-#{statusId}")

            if width
                column.css('max-width', width)
            else
                column.css("max-width", maxColumnWidth)

        refreshTaskboardTableWidth = () =>
            columnWidths = []

            columns = $el.find(".task-colum-name")

            columnWidths = _.map columns, (column) ->
                return $(column).outerWidth(true)

            totalWidth = _.reduce columnWidths, (total, width) ->
                return total + width

            $el.find('.taskboard-table-inner').css("width", totalWidth)

        recalculateStatusColumnWidth = (statusId) =>
            #unassigned ceil
            statusFoldedWidth = getCeilWidth(null, statusId)

            _.forEach $scope.userstories, (us) ->
                width = getCeilWidth(us.id, statusId)
                statusFoldedWidth = width if width > statusFoldedWidth

            setStatusColumnWidth(statusId, statusFoldedWidth)

        recalculateTaskboardWidth = () =>
            _.forEach $scope.taskStatusList, (status) ->
                recalculateStatusColumnWidth(status.id)

            refreshTaskboardTableWidth()

            return

    return {link: link}

module.directive("tgTaskboardSquishColumn", ["$tgResources", TaskboardSquishColumnDirective])
