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
# File: home.service.coffee
###

groupBy = @.taiga.groupBy

class TaskboardTasksService extends taiga.Service
    @.$inject = []
    constructor: () ->
        @.tasksRaw = []
        @.usTasks = Immutable.Map()

    init: (project, usersById) ->
        @.project = project
        @.usersById = usersById

    add: (task) ->
        @.tasksRaw = @.tasksRaw.concat(task)
        @.refresh()

    set: (tasks) ->
        @.tasksRaw = tasks
        @.refresh()

    setUserstories: (userstories) ->
        @.userstories = userstories

    getTask: (id) ->
        findedTask = null

        @.usTasks.forEach (us) ->
            us.forEach (status) ->
                findedTask = status.find (task) -> return task.get('id') == id

                return false if findedTask

            return false if findedTask

        return findedTask

    replace: (task) ->
        @.usTasks = @.usTasks.map (us) ->
            return us.map (status) ->
                findedIndex = status.findIndex (usItem) ->
                    return usItem.get('id') == us.get('id')

                if findedIndex != -1
                    status = status.set(findedIndex, task)

                return status

    getTaskModel: (id) ->
        return _.find @.tasksRaw, (task) -> return task.id == id

    replaceModel: (task) ->
        @.tasksRaw = _.map @.tasksRaw, (it) ->
            if task.id == it.id
                return task
            else
                return it

        @.refresh()

    move: (id, usId, statusId, index) ->
        task = @.getTaskModel(id)

        taskByUsStatus = _.filter @.tasksRaw, (task) =>
            return task.status == statusId && task.user_story == usId

        taskByUsStatus = _.sortBy(taskByUsStatus, "taskboard_order")

        if task.status != statusId || task.user_story != usId
            taskByUsStatus.splice(index, 0, task)

            task.status = statusId
            task.user_story = usId
        else
            oldIndex = _.findIndex taskByUsStatus, (it) ->
                return it.id == task.id

            taskByUsStatus.splice(oldIndex, 1)
            taskByUsStatus.splice(index, 0, task)

        modified = @.resortTasks(taskByUsStatus)

        @.refresh()

        return modified

    resortTasks: (tasks) ->
        items = []
        for item, index in tasks
            item.taskboard_order = index
            if item.isModified()
                items.push(item)

        return items

    refresh: ->
        tasks = @.tasksRaw

        tasks = _.sortBy(tasks, 'taskboard_order')
        taskStatusList = _.sortBy(@.project.task_statuses, "order")

        usTasks = {}

        # Iterate over all userstories and
        # null userstory for unassigned tasks
        for us in _.union(@.userstories, [{id:null}])
            usTasks[us.id] = {}
            for status in taskStatusList
                usTasks[us.id][status.id] = []

        for taskModel in tasks
            if usTasks[taskModel.user_story]? and usTasks[taskModel.user_story][taskModel.status]?
                task = {}
                task.model = taskModel.getAttrs()
                task.id = taskModel.id
                task.assigned_to = @.usersById[taskModel.assigned_to]
                task.colorized_tags = _.map task.model.tags, (tag) =>
                    color = @.project.tags_colors[tag]
                    return {name: tag, color: color}

                usTasks[taskModel.user_story][taskModel.status].push(task)

        console.log usTasks

        @.usTasks = Immutable.fromJS(usTasks)

angular.module("taigaKanban").service("tgTaskboardTasks", TaskboardTasksService)
