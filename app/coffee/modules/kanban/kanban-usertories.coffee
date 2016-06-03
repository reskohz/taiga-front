###
# Copyright (C) 2014-2016 Taiga Agile LLC <taiga@taiga.io>
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
# File: kanban-userstories.service.coffee
###

groupBy = @.taiga.groupBy

class KanbanUserstoriesService extends taiga.Service
    @.$inject = []

    constructor: () ->
        @.userstoriesRaw = []
        @.archivedStatus = []
        @.statusHide = []
        @.usByStatus = Immutable.Map()

    init: (project, usersById) ->
        @.project = project
        @.usersById = usersById

    set: (userstories) ->
        @.userstoriesRaw = userstories
        @.refresh()

    add: (us) ->
        @.userstoriesRaw = @.userstoriesRaw.concat(us)
        @.refresh()

    addArchivedStatus: (statusId) ->
        @.archivedStatus.push(statusId)

    isUsInArchivedHiddenStatus: (usId) ->
        us = @.getUsModel(usId)

        return @.archivedStatus.indexOf(us.status) != -1 &&
            @.statusHide.indexOf(us.status) != -1

    hideStatus: (statusId) ->
        @.deleteStatus(statusId)
        @.statusHide.push(statusId)

    showStatus: (statusId) ->
        _.remove @.statusHide, (it) -> return it == statusId

    getStatus: (statusId) ->
        return _.filter @.userstoriesRaw, (us) -> return us.status == statusId

    deleteStatus: (statusId) ->
        toDelete = _.filter @.userstoriesRaw, (us) -> return us.status == statusId
        toDelete = _.map (it) -> return it.id

        @.archived = _.difference(@.archived, toDelete)

        @.userstoriesRaw = _.filter @.userstoriesRaw, (us) -> return us.status != statusId

        @.refresh()

    move: (id, statusId, index) ->
        us = @.getUsModel(id)

        usByStatus = _.filter @.userstoriesRaw, (us) =>
            return us.status == statusId

        usByStatus = _.sortBy(usByStatus, "kanban_order")

        if us.status != statusId
            usByStatus.splice(index, 0, us)

            us.status = statusId
        else
            oldIndex = _.findIndex usByStatus, (it) ->
                return it.id == us.id

            usByStatus.splice(oldIndex, 1)
            usByStatus.splice(index, 0, us)

        modified = @.resortUserStories(usByStatus)

        @.refresh()

        return modified

    resortUserStories: (userstories) ->
        items = []
        for item, index in userstories
            item.kanban_order = index
            if item.isModified()
                items.push(item)

        return items

    replace: (us) ->
        @.usByStatus = @.usByStatus.map (status) ->
            findedIndex = status.findIndex (usItem) ->
                return usItem.get('id') == us.get('id')

            if findedIndex != -1
                status = status.set(findedIndex, us)

            return status

    replaceModel: (us) ->
        @.userstoriesRaw = _.map @.userstoriesRaw, (usItem) ->
            if us.id == usItem.id
                return us
            else
                return usItem

        @.refresh()

    getUs: (id) ->
        findedUs = null

        @.usByStatus.forEach (status) ->
            findedUs = status.find (us) -> return us.get('id') == id

            return false if findedUs

        return findedUs

    getUsModel: (id) ->
        return _.find @.userstoriesRaw, (us) -> return us.id == id

    refresh: ->
        userstories = @.userstoriesRaw

        userstories = _.sortBy(userstories, "kanban_order")

        userstories = _.map userstories, (usModel) =>
            us = {}
            us.model = usModel.getAttrs()
            us.id = usModel.id
            us.assigned_to = @.usersById[usModel.assigned_to]
            us.colorized_tags = _.map us.model.tags, (tag) =>
                color = @.project.tags_colors[tag]
                return {name: tag, color: color}

            return us

        usByStatus = _.groupBy userstories, (us) ->
            return us.model.status

        @.usByStatus = Immutable.fromJS(usByStatus)

angular.module("taigaKanban").service("tgKanbanUserstories", KanbanUserstoriesService)
