###* @preserve OverlappingMarkerSpiderfier
https://github.com/jaredhobbs/OverlappingMarkerSpiderfier
Copyright (c) 2011 - 2012 George MacKerron
Released under the MIT licence: http://opensource.org/licenses/mit-license
Mapstraction port by Jared Hobbs
Note: The Mapstraction API must be included *before* this code
###

# NB. string literal properties -- object['key'] -- are for Closure Compiler ADVANCED_OPTIMIZATION

return unless this['mxn']?  # return from wrapper func without doing anything

class @['OverlappingMarkerSpiderfier']
  p = @::  # this saves a lot of repetition of .prototype that isn't optimized away
  p['VERSION'] = '0.3.1'

  twoPi = Math.PI * 2

  p['keepSpiderfied']  = no          # yes -> don't unspiderfy when a marker is selected
  p['markersWontHide'] = no          # yes -> a promise you won't hide markers, so we needn't check
  p['markersWontMove'] = no          # yes -> a promise you won't move markers, so we needn't check

  p['nearbyDistance'] = 20           # spiderfy markers within this range of the one clicked, in px

  p['circleSpiralSwitchover'] = 9    # show spiral instead of circle from this marker count upwards
                                     # 0 -> always spiral; Infinity -> always circle
  p['circleFootSeparation'] = 23     # related to circumference of circle
  p['circleStartAngle'] = twoPi / 12
  p['spiralFootSeparation'] = 26     # related to size of spiral (experiment!)
  p['spiralLengthStart'] = 11        # ditto
  p['spiralLengthFactor'] = 4        # ditto

  p['spiderfiedZIndex'] = 1000       # ensure spiderfied markers are on top
  p['usualLegZIndex'] = 10           # for legs
  p['highlightedLegZIndex'] = 20     # ensure highlighted leg is always on top

  p['legWeight'] = 1.5
  p['legColors'] =
      'usual': {}
      'highlighted': {}

  lcU = p['legColors']['usual']
  lcH = p['legColors']['highlighted']
  lcU[mxn.Mapstraction.HYBRID] = lcU[mxn.Mapstraction.SATELLITE] = '#FFFFFF'
  lcH[mxn.Mapstraction.HYBRID] = lcH[mxn.Mapstraction.SATELLITE] = '#F00F00'
  lcU[mxn.Mapstraction.PHYSICAL] = lcU[mxn.Mapstraction.ROAD] = '#444444'
  lcH[mxn.Mapstraction.PHYSICAL] = lcH[mxn.Mapstraction.ROAD] = '#F00F00'

  # Note: it's OK that this constructor comes after the properties, because a function defined by a 
  # function declaration can be used before the function declaration itself
  constructor: (@map, opts = {}) ->
      (@[k] = v) for own k, v of opts
      @initMarkerArrays()
      @listeners = {}
      @map.click.addHandler(=> @['unspiderfy']())
      @map.changeZoom.addHandler(=> @['unspiderfy']())

  p['initMarkerArrays'] = ->
      @markers = []
      @markerListenerRefs = []

  p['addMarker'] = (marker) ->
      return @ if marker['_oms']?
      marker['_oms'] = yes
      markerListener = => @spiderListener(marker)
      marker.click.addHandler(markerListener)
      @markerListenerRefs.push(markerListener)
      @markers.push(marker)
      @  # return self, for chaining

  p['markerChangeListener'] = (marker, positionChanged) ->
      if marker['_omsData']? and (positionChanged or not marker.onmap) and not (@spiderfying? or @unspiderfying?)
          @unspiderfy(if positionChanged then marker else null)

  p['getMarkers'] = -> @markers[0..]  # returns a copy, so no funny business

  p['removeMarker'] = (marker) ->
      @['unspiderfy']() if marker['_omsData']?  # otherwise it'll be stuck there forever!
      i = @arrIndexOf(@markers, marker)
      return @ if i < 0
      markerListener = @markerListenerRefs.splice(i, 1)[0]
      marker.click.removeHandler(markerListener)
      delete marker['_oms']
      @markers.splice(i, 1)
      @  # return self, for chaining

  p['clearMarkers'] = ->
      @['unspiderfy']()
      for marker, i in @markers
          markerListener = @markerListenerRefs[i]
          marker.click.removeHandler(markerListener)
          delete marker['_oms']
      @initMarkerArrays()
      @  # return self, for chaining

  # available listeners: click(marker), spiderfy(markers), unspiderfy(markers)
  p['addListener'] = (event, func) ->
      (@listeners[event] ?= []).push(func)
      @  # return self, for chaining

  p['removeListener'] = (event, func) ->
      i = @arrIndexOf(@listeners[event], func)
      @listeners[event].splice(i, 1) unless i < 0
      @  # return self, for chaining

  p['clearListeners'] = (event) ->
      @listeners[event] = []
      @  # return self, for chaining

  p['trigger'] = (event, args...) ->
      func(args...) for func in (@listeners[event] ? [])

  p['generatePtsCircle'] = (count, centerPt) ->
      circumference = @['circleFootSeparation'] * (2 + count)
      legLength = circumference / twoPi  # = radius from circumference
      angleStep = twoPi / count
      for i in [0...count]
          angle = @['circleStartAngle'] + i * angleStep
          tmp = new mxn.LatLonPoint()
          tmp.fromProprietary(@map.api, {lat: centerPt.lat + legLength * Math.cos(angle), lon: centerPt.lon + legLength * Math.sin(angle)})
          @llToPt(tmp)

  p['generatePtsSpiral'] = (count, centerPt) ->
      legLength = @['spiralLengthStart']
      angle = 0
      for i in [0...count]
          angle += @['spiralFootSeparation'] / legLength + i * 0.0005
          tmp = new mxn.LatLonPoint()
          tmp.fromProprietary(@map.api, {lat: centerPt.lat + legLength * Math.cos(angle), lon: centerPt.lon + legLength * Math.sin(angle)})
          pt = @llToPt(tmp)
          legLength += twoPi * @['spiralLengthFactor'] / angle
          pt

  p['spiderListener'] = (marker) ->
      markerSpiderfied = marker['_omsData']? @['unspiderfy']() unless markerSpiderfied and @['keepSpiderfied']
      if markerSpiderfied or @map.getMapType() is 'GoogleEarthAPI'  # don't spiderfy in GE Plugin!
          @trigger('click', marker)
      else
          nearbyMarkerData = []
          nonNearbyMarkers = []
          nDist = @['nearbyDistance']
          pxSq = nDist * nDist
          markerPt = @llToPt(marker.location)
          for m in @markers
              mPt = @llToPt(m.location)
              if @ptDistanceSq(mPt, markerPt) < pxSq
                  nearbyMarkerData.push(marker: m, markerPt: mPt)
              else
                  nonNearbyMarkers.push(m)
          if nearbyMarkerData.length is 1  # 1 => the one clicked => none nearby
              @trigger('click', marker)
          else
              @spiderfy(nearbyMarkerData, nonNearbyMarkers)

  p['markersNearMarker'] = (marker, firstOnly = no) ->
      nDist = @['nearbyDistance']
      pxSq = nDist * nDist
      markerPt = @llToPt(marker.location)
      markers = []
      for m in @markers
          continue if m is marker or not m.map? or not m.onmap
          mPt = @llToPt(m['_omsData']?.usualPosition ? m.location)
          if @ptDistanceSq(mPt, markerPt) < pxSq
              markers.push(m)
              break if firstOnly
      markers

  p['markersNearAnyOtherMarker'] = ->  # *very* much quicker than calling markersNearMarker in a loop
      nDist = @['nearbyDistance']
      pxSq = nDist * nDist
      mData = for m in @markers
          {pt: @llToPt(m['_omsData']?.usualPosition ? m.location), willSpiderfy: no}
      for m1, i1 in @markers
          continue unless m1.map? and m1.onmap
          m1Data = mData[i1]
          continue if m1Data.willSpiderfy
          for m2, i2 in @markers
              continue if i2 is i1
              continue unless m2.map? and m2.onmap
              m2Data = mData[i2]
              continue if i2 < i1 and not m2Data.willSpiderfy
              if @ptDistanceSq(m1Data.pt, m2Data.pt) < pxSq
                  m1Data.willSpiderfy = m2Data.willSpiderfy = yes
                  break
      m for m, i in @markers when mData[i].willSpiderfy

  p['spiderfy'] = (markerData, nonNearbyMarkers) ->
      @spiderfying = yes
      numFeet = markerData.length
      bodyPt = @ptAverage(md.markerPt for md in markerData)
      footPts = if numFeet >= @['circleSpiralSwitchover']
          @generatePtsSpiral(numFeet, bodyPt).reverse()  # match from outside in => less criss-crossing
      else
          @generatePtsCircle(numFeet, bodyPt)
      spiderfiedMarkers = for footPt in footPts
          footLl = new mxn.LatLonPoint()
          footLl.fromProprietary(@map.api, footPt)
          footLl.lng = footLl.lon + 3
          footLl.lat += 3
          nearestMarkerDatum = @minExtract(markerData, (md) => @ptDistanceSq(md.markerPt, footPt))
          marker = nearestMarkerDatum.marker
          leg = new mxn.Polyline([marker.location, footLl])
          leg.setColor(@['legColors']['usual'][@map.getMapType()])
          leg.setWidth(@['legWeight'])
          leg.setAttribute('zIndex', @['usualLegZIndex'])
          @map.addPolyline(leg)
          marker['_omsData'] =
              usualPosition: marker.location
              leg: leg
          marker.lat = footLl.lat
          marker.lon = marker.lng = footLl.lon
          marker.setAttribute('zIndex', Math.round(@['spiderfiedZIndex'] + footPt.lat))  # lower markers cover higher
          marker
      delete @spiderfying
      @spiderfied = yes
      @trigger('spiderfy', spiderfiedMarkers, nonNearbyMarkers)

  p['unspiderfy'] = (markerNotToMove = null) ->
      return @ unless @spiderfied?
      @unspiderfying = yes
      unspiderfiedMarkers = []
      nonNearbyMarkers = []
      for marker in @markers
          if marker['_omsData']?
              @map.removePolyline(marker['_omsData'].leg)
              marker.lat = marker['_omsData'].usualPosition.lat unless marker is markerNotToMove
              marker.lon = marker.lng = marker['_omsData'].usualPosition.lon unless marker is markerNotToMove
              marker.setAttribute('zIndex', null)
              delete marker['_omsData']
              unspiderfiedMarkers.push(marker)
          else
              nonNearbyMarkers.push(marker)
      delete @unspiderfying
      delete @spiderfied
      @trigger('unspiderfy', unspiderfiedMarkers, nonNearbyMarkers)
      @  # return self, for chaining

  p['ptDistanceSq'] = (pt1, pt2) ->
      dx = pt1.lon - pt2.lon
      dy = pt1.lat - pt2.lat
      dx * dx + dy * dy

  p['ptAverage'] = (pts) ->
      sumX = sumY = 0
      for pt in pts
          sumX += pt.lon; sumY += pt.lat
      numPts = pts.length
      tmp = new mxn.LatLonPoint()
      tmp.fromProprietary(@map.api, {lon: sumX / numPts, lat: sumY / numPts})
      @llToPt(tmp)

  p['llToPt'] = (ll) -> ll.toProprietary(@map.api)

  p['minExtract'] = (set, func) ->  # destructive! returns minimum, and also removes it from the set
      bestIndex = 0
      bestVal = Number.MAX_VALUE
      for item, index in set
          val = func(item)
          if val < bestVal
              bestVal = val
              bestIndex = index
      set.splice(bestIndex, 1)[0]

  p['arrIndexOf'] = (arr, obj) ->
      return arr.indexOf(obj) if arr.indexOf?
      (return i if o is obj) for o, i in arr
      -1

