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
# File: modules/kanban/main.coffee
###

taiga = @.taiga

mixOf = @.taiga.mixOf
toggleText = @.taiga.toggleText
scopeDefer = @.taiga.scopeDefer
bindOnce = @.taiga.bindOnce
groupBy = @.taiga.groupBy
timeout = @.taiga.timeout
bindMethods = @.taiga.bindMethods

module = angular.module("taigaKanban")

# Vars

defaultViewMode = "maximized"
viewModes = [
    "maximized",
    "minimized"
]


#############################################################################
## Kanban Controller
#############################################################################

class KanbanController extends mixOf(taiga.Controller, taiga.PageMixin, taiga.FiltersMixin)
    @.$inject = [
        "$scope",
        "$rootScope",
        "$tgRepo",
        "$tgConfirm",
        "$tgResources",
        "tgResources",
        "$routeParams",
        "$q",
        "$tgLocation",
        "tgAppMetaService",
        "$tgNavUrls",
        "$tgEvents",
        "$tgAnalytics",
        "$translate",
        "tgErrorHandlingService",
        "$tgModel",
        "tgKanbanUserstories",
        "$tgStorage"
    ]

    constructor: (@scope, @rootscope, @repo, @confirm, @rs, @rs2, @params, @q, @location,
                  @appMetaService, @navUrls, @events, @analytics, @translate, @errorHandlingService,
                  @model, @kanbanUserstoriesService, @storage) ->

        bindMethods(@)
        @.zoom = @storage.get("kanban_zoom") or 0

        @scope.sectionName = @translate.instant("KANBAN.SECTION_NAME")
        @scope.statusViewModes = {}
        @.initializeEventHandlers()

        promise = @.loadInitialData()

        # On Success
        promise.then =>
            title = @translate.instant("KANBAN.PAGE_TITLE", {projectName: @scope.project.name})
            description = @translate.instant("KANBAN.PAGE_DESCRIPTION", {
                projectName: @scope.project.name,
                projectDescription: @scope.project.description
            })
            @appMetaService.setAll(title, description)

        # On Error
        promise.then null, @.onInitialDataError.bind(@)

        taiga.defineImmutableProperty @.scope, "usByStatus", () =>
            return @kanbanUserstoriesService.usByStatus

    initializeEventHandlers: ->
        @scope.$on "usform:new:success", (event, us) =>
            @.refreshTagsColors().then () =>
                @kanbanUserstoriesService.add(us)

            @analytics.trackEvent("userstory", "create", "create userstory on kanban", 1)

        @scope.$on "usform:bulk:success", (event, uss) =>
            @.refreshTagsColors().then () =>
                @kanbanUserstoriesService.add(uss)

            @analytics.trackEvent("userstory", "create", "bulk create userstory on kanban", 1)

        @scope.$on "usform:edit:success", (event, us) =>
            @.refreshTagsColors().then () =>
                @kanbanUserstoriesService.replaceModel(us)

        @scope.$on("assigned-to:added", @.onAssignedToChanged)
        @scope.$on("kanban:us:move", @.moveUs)
        @scope.$on("kanban:show-userstories-for-status", @.loadUserStoriesForStatus)
        @scope.$on("kanban:hide-userstories-for-status", @.hideUserStoriesForStatus)

    addNewUs: (type, statusId) ->
        switch type
            when "standard" then @rootscope.$broadcast("usform:new", @scope.projectId, statusId, @scope.usStatusList)
            when "bulk" then @rootscope.$broadcast("usform:bulk", @scope.projectId, statusId)

    editUs: (id) ->
        us = @kanbanUserstoriesService.getUs(id)
        us = us.set('loading', true)
        @kanbanUserstoriesService.replace(us)

        @rs.userstories.getByRef(us.getIn(['model', 'project']), us.getIn(['model', 'ref']))
         .then (editingUserStory) =>
            @rs2.attachments.list("us", us.get('id'), us.getIn(['model', 'project'])).then (attachments) =>
                @rootscope.$broadcast("usform:edit", editingUserStory, attachments.toJS())

                us = us.set('loading', false)
                @kanbanUserstoriesService.replace(us)

    showPlaceHolder: (statusId) ->
        if @scope.usStatusList[0].id == statusId &&
          !@kanbanUserstoriesService.userstoriesRaw.length
            return true

        return false

    isUsInArchivedHiddenStatus: (usId) ->
        return @kanbanUserstoriesService.isUsInArchivedHiddenStatus(usId)

    changeUsAssignedTo: (id) ->
        us = @kanbanUserstoriesService.getUsModel(id)

        @rootscope.$broadcast("assigned-to:add", us)

    # Scope Events Handlers

    onAssignedToChanged: (ctx, userid, usModel) ->
        usModel.assigned_to = userid

        @kanbanUserstoriesService.replaceModel(usModel)

        promise = @repo.save(usModel)
        promise.then null, ->
            console.log "FAIL" # TODO

    refreshTagsColors: ->
        return @rs.projects.tagsColors(@scope.projectId).then (tags_colors) =>
            @scope.project.tags_colors = tags_colors

    loadUserstories: ->
        params = {
            status__is_archived: false,
            include_attachments: true,
            include_tasks: true
        }

        promise = @rs.userstories.listAll(@scope.projectId, params).then (userstories) =>
            @kanbanUserstoriesService.init(@scope.project, @scope.usersById)
            @kanbanUserstoriesService.set(userstories)

            # The broadcast must be executed when the DOM has been fully reloaded.
            # We can't assure when this exactly happens so we need a defer
            scopeDefer @scope, =>
                @scope.$broadcast("userstories:loaded", userstories)

            return userstories

        promise.then( => @scope.$broadcast("redraw:wip"))

        return promise

    loadUserStoriesForStatus: (ctx, statusId) ->
        params = { status: statusId }
        return @rs.userstories.listAll(@scope.projectId, params).then (userstories) =>
            @scope.$broadcast("kanban:shown-userstories-for-status", statusId, userstories)

            return userstories

    hideUserStoriesForStatus: (ctx, statusId) ->
        @scope.$broadcast("kanban:hidden-userstories-for-status", statusId)

    loadKanban: ->
        return @q.all([
            @.refreshTagsColors(),
            @.loadUserstories()
        ])

    loadProject: ->
        return @rs.projects.getBySlug(@params.pslug).then (project) =>
            if not project.is_kanban_activated
                @errorHandlingService.permissionDenied()

            @scope.projectId = project.id
            @scope.project = project
            @scope.projectId = project.id
            @scope.points = _.sortBy(project.points, "order")
            @scope.pointsById = groupBy(project.points, (x) -> x.id)
            @scope.usStatusById = groupBy(project.us_statuses, (x) -> x.id)
            @scope.usStatusList = _.sortBy(project.us_statuses, "order")

            @.generateStatusViewModes()

            @scope.$emit("project:loaded", project)
            return project

    initializeSubscription: ->
        routingKey1 = "changes.project.#{@scope.projectId}.userstories"
        @events.subscribe @scope, routingKey1, (message) =>
            @.loadUserstories()

    loadInitialData: ->
        promise = @.loadProject()
        return promise.then (project) =>
            @.fillUsersAndRoles(project.members, project.roles)
            @.initializeSubscription()
            @.loadKanban()


    ## View Mode methods

    generateStatusViewModes: ->
        storedStatusViewModes = @rs.kanban.getStatusViewModes(@scope.projectId)

        @scope.statusViewModes = {}
        for status in @scope.usStatusList
            mode = storedStatusViewModes[status.id] || defaultViewMode

            @scope.statusViewModes[status.id] = mode

        @.storeStatusViewModes()

    storeStatusViewModes: ->
        @rs.kanban.storeStatusViewModes(@scope.projectId, @scope.statusViewModes)

    updateStatusViewMode: (statusId, newViewMode) ->
        @scope.statusViewModes[statusId] = newViewMode
        @.storeStatusViewModes()

    isMaximized: (statusId) ->
        mode = @scope.statusViewModes[statusId] or defaultViewMode
        return mode == 'maximized'

    isMinimized: (statusId) ->
        mode = @scope.statusViewModes[statusId] or defaultViewMode
        return mode == 'minimized'

    # Utils methods

    prepareBulkUpdateData: (uses, field="kanban_order") ->
        return _.map(uses, (x) -> {"us_id": x.id, "order": x[field]})

    moveUs: (ctx, us, oldStatusId, newStatusId, index) ->
        us = @kanbanUserstoriesService.getUsModel(us.get('id'))

        itemsToSave = @kanbanUserstoriesService.move(us.id, newStatusId, index)

        # Persist the userstory
        promise = @repo.save(us)

        # Rehash userstories order field
        # and persist in bulk all changes.
        promise = promise.then =>
            itemsToSave = _.reject(itemsToSave, {"id": us.id})
            data = @.prepareBulkUpdateData(itemsToSave)

            return @rs.userstories.bulkUpdateKanbanOrder(us.project, data).then =>
                return itemsToSave

        return promise


module.controller("KanbanController", KanbanController)

#############################################################################
## Kanban Directive
#############################################################################

KanbanDirective = ($repo, $rootscope) ->
    link = ($scope, $el, $attrs) ->
        tableBodyDom = $el.find(".kanban-table-body")

        tableBodyDom.on "scroll", (event) ->
            target = angular.element(event.currentTarget)
            tableHeaderDom = $el.find(".kanban-table-header .kanban-table-inner")
            tableHeaderDom.css("left", -1 * target.scrollLeft())

        $scope.$on "$destroy", ->
            $el.off()

    return {link: link}

module.directive("tgKanban", ["$tgRepo", "$rootScope", KanbanDirective])

#############################################################################
## Kanban Archived Status Column Header Control
#############################################################################

KanbanArchivedStatusHeaderDirective = ($rootscope, $translate, kanbanUserstoriesService) ->
    showArchivedText = $translate.instant("KANBAN.ACTION_SHOW_ARCHIVED")
    hideArchivedText = $translate.instant("KANBAN.ACTION_HIDE_ARCHIVED")

    link = ($scope, $el, $attrs) ->
        status = $scope.$eval($attrs.tgKanbanArchivedStatusHeader)
        hidden = true

        kanbanUserstoriesService.addArchivedStatus(status.id)
        kanbanUserstoriesService.hideStatus(status.id)

        $scope.class = "icon-watch"
        $scope.title = showArchivedText

        $el.on "click", (event) ->
            hidden = not hidden

            $scope.$apply ->
                if hidden
                    $scope.class = "icon-watch"
                    $scope.title = showArchivedText
                    $rootscope.$broadcast("kanban:hide-userstories-for-status", status.id)

                    kanbanUserstoriesService.hideStatus(status.id)
                else
                    $scope.class = "icon-unwatch"
                    $scope.title = hideArchivedText
                    $rootscope.$broadcast("kanban:show-userstories-for-status", status.id)

                    kanbanUserstoriesService.showStatus(status.id)

        $scope.$on "$destroy", ->
            $el.off()

    return {link:link}

module.directive("tgKanbanArchivedStatusHeader", [ "$rootScope", "$translate", "tgKanbanUserstories", KanbanArchivedStatusHeaderDirective])


#############################################################################
## Kanban Archived Status Column Intro Directive
#############################################################################

KanbanArchivedStatusIntroDirective = ($translate, kanbanUserstoriesService) ->
    userStories = []

    link = ($scope, $el, $attrs) ->
        hiddenUserStoriexText = $translate.instant("KANBAN.HIDDEN_USER_STORIES")
        status = $scope.$eval($attrs.tgKanbanArchivedStatusIntro)
        $el.text(hiddenUserStoriexText)

        updateIntroText = (hasArchived) ->
            if hasArchived
                $el.text("")
            else
                $el.text(hiddenUserStoriexText)

        $scope.$on "kanban:us:move", (ctx, itemUs, oldStatusId, newStatusId, itemIndex) ->
            hasArchived = !!kanbanUserstoriesService.getStatus(newStatusId).length
            updateIntroText(hasArchived)

        $scope.$on "kanban:shown-userstories-for-status", (ctx, statusId, userStoriesLoaded) ->
            if statusId == status.id
                kanbanUserstoriesService.deleteStatus(statusId)
                kanbanUserstoriesService.add(userStoriesLoaded)

                hasArchived = !!kanbanUserstoriesService.getStatus(statusId).length
                updateIntroText(hasArchived)

        $scope.$on "kanban:hidden-userstories-for-status", (ctx, statusId) ->
            if statusId == status.id
                updateIntroText(false)

        $scope.$on "$destroy", ->
            $el.off()

    return {link:link}

module.directive("tgKanbanArchivedStatusIntro", ["$translate", "tgKanbanUserstories", KanbanArchivedStatusIntroDirective])

#############################################################################
## Kanban Squish Column Directive
#############################################################################

KanbanSquishColumnDirective = (rs) ->

    link = ($scope, $el, $attrs) ->
        $scope.$on "project:loaded", (event, project) ->
            $scope.folds = rs.kanban.getStatusColumnModes(project.id)
            updateTableWidth()

        $scope.foldStatus = (status) ->
            $scope.folds[status.id] = !!!$scope.folds[status.id]
            rs.kanban.storeStatusColumnModes($scope.projectId, $scope.folds)
            updateTableWidth()
            return

        updateTableWidth = ->
            columnWidths = _.map $scope.usStatusList, (status) ->
                if $scope.folds[status.id]
                    return 40
                else
                    return 310
            totalWidth = _.reduce columnWidths, (total, width) ->
                return total + width
            $el.find('.kanban-table-inner').css("width", totalWidth)

    return {link: link}

module.directive("tgKanbanSquishColumn", ["$tgResources", KanbanSquishColumnDirective])

#############################################################################
## Kanban WIP Limit Directive
#############################################################################

KanbanWipLimitDirective = ->
    link = ($scope, $el, $attrs) ->
        status = $scope.$eval($attrs.tgKanbanWipLimit)

        redrawWipLimit = =>
            $el.find(".kanban-wip-limit").remove()
            timeout 200, =>
                element = $el.find("tg-card")[status.wip_limit]
                if element
                    angular.element(element).before("<div class='kanban-wip-limit'></div>")

        if status and not status.is_archived
            $scope.$on "redraw:wip", redrawWipLimit
            $scope.$on "kanban:us:move", redrawWipLimit
            $scope.$on "usform:new:success", redrawWipLimit
            $scope.$on "usform:bulk:success", redrawWipLimit

        $scope.$on "$destroy", ->
            $el.off()

    return {link: link}

module.directive("tgKanbanWipLimit", KanbanWipLimitDirective)
