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
# File: card-slideshow.controller.coffee
###

class CardSlideshowController
    @.$inject = []

    constructor: () ->
        @.attachments = Immutable.List()
        @.index = 0

    getImages: () ->
        return @.attachments.filter (elm) -> return !!elm.get('thumbnail_card_url')

    hasPagination: () ->
        images = @.getImages()

        return images.size > 1

    next: () ->
        image = @.attachments.slice(@.index + 1).find (attachment) ->
            return !!attachment.get('thumbnail_card_url')

        if !image
            image = @.attachments.find (attachment) ->
                return !!attachment.get('thumbnail_card_url')

        @.index = @.attachments.findIndex (attachment) ->
            return attachment.get('id') == image.get('id')

    previous: () ->
        image = @.attachments.slice(0, @.index).find (attachment) ->
            return !!attachment.get('thumbnail_card_url')

        if !image
            image = @.attachments.findLast (attachment) ->
                return !!attachment.get('thumbnail_card_url')

        @.index = @.attachments.findLastIndex (attachment) ->
            return attachment.get('id') == image.get('id')

angular.module('taigaComponents').controller('CardSlideshow', CardSlideshowController)
