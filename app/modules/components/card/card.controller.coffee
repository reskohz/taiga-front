###
# Copyright (C) 2014-2015 Taiga Agile LLC <taiga@taiga.io>
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
# File: card.controller.coffee
###

class CardController
    @.$inject = []

    getClosedTasks: () ->
        return @.item.getIn(['model', 'tasks']).filter (task) -> return task.get('is_closed');

    closedTasksPercent: () ->
        return @.getClosedTasks().size * 100 / @.item.getIn(['model', 'tasks']).size

    getPermissionsKey: () ->
        if @.type == 'task'
            return 'modify_task'
        else
            return 'modify_us'

    getNavKey: () ->
        if @.type == 'task'
            return 'project-tasks-detail'
        else
            return 'project-userstories-detail'

angular.module('taigaComponents').controller('Card', CardController)
