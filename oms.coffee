###* @preserve OverlappingMarkerSpiderfier
https://github.com/jaredhobbs/OverlappingMarkerSpiderfier
Copyright (c) 2011 - 2012 George MacKerron
Released under the MIT licence: http://opensource.org/licenses/mit-license
Mapstraction port by Jared Hobbs
Note: The OpenLayers API must be included *before* this code
###

# NB. string literal properties -- object['key'] -- are for Closure Compiler ADVANCED_OPTIMIZATION

return unless this['OpenLayers']?  # return from wrapper func without doing anything

class @['OverlappingMarkerSpiderfier']
  p = @::  # this saves a lot of repetition of .prototype that isn't optimized away
  p['VERSION'] = '0.2.5'

  twoPi = Math.PI * 2

  p['keepSpiderfied']  = no          # yes -> don't unspiderfy when a marker is selected
  p['nearbyDistance'] = 20           # spiderfy markers within this range of the one clicked, in px

  p['circleSpiralSwitchover'] = 9    # show spiral instead of circle from this marker count upwards
                                     # 0 -> always spiral; Infinity -> always circle
  p['circleFootSeparation'] = 25     # related to circumference of circle
  p['circleStartAngle'] = twoPi / 12
  p['spiralFootSeparation'] = 28     # related to size of spiral (experiment!)
  p['spiralLengthStart'] = 11        # ditto
  p['spiralLengthFactor'] = 5        # ditto

  p['legWeight'] = 1.5
  p['legColors'] =
      'usual': '#222222'
      'highlighted': '#f00f00'

  # Note: it's OK that this constructor comes after the properties, because a function defined by a 
  # function declaration can be used before the function declaration itself
  constructor: (@map, opts = {}) ->
      (@[k] = v) for own k, v of opts
      @initMarkerArrays()
      @listeners = {}
      @map.events.register(e, @map, => @['unspiderfy']()) for e in ['mousedown', 'zoomend']

  p['initMarkerArrays'] = ->
      @markers = []
      @markerListeners = []

  p['addMarker'] = (marker) ->
      return @ if marker['_oms']?
      marker['_oms'] = yes
      markerListener = => @spiderListener(marker)
      marker.events.register('mousedown', marker, markerListener)
      @markerListeners.push(markerListener)
      @markers.push(marker)
      @  # return self, for chaining


  p['markerChangeListener'] = (marker, positionChanged) ->
      if marker['_omsData']? and (positionChanged or not marker.isDrawn()) and not (@spiderfying? or @unspiderfying?)
          @unspiderfy(if positionChanged then marker else null)

  p['getMarkers'] = -> @markers[0..]  # returns a copy, so no funny business

  p['removeMarker'] = (marker) ->
      @['unspiderfy']() if marker['_omsData']?  # otherwise it'll be stuck there forever!
      i = @arrIndexOf(@markers, marker)
      return @ if i < 0
      markerListener = @markerListeners.splice(i, 1)[0]
      marker.events.unregister('mousedown', marker, markerListener)
      delete marker['_oms']
      @markers.splice(i, 1)
      @  # return self, for chaining

  p['clearMarkers'] = ->
      @['unspiderfy']()
      for marker, i in @markers
          markerListener = @markerListeners[i]
          marker.events.unregister('mousedown', marker, markerListener)
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
          new OpenLayers.Geometry.Point(centerPt.x + legLength * Math.cos(angle), centerPt.y + legLength * Math.sin(angle))

  p['generatePtsSpiral'] = (count, centerPt) ->
      legLength = @['spiralLengthStart']
      angle = 0
      for i in [0...count]
          angle += @['spiralFootSeparation'] / legLength + i * 0.0005
          pt = new OpenLayers.Geometry.Point(centerPt.x + legLength * Math.cos(angle), centerPt.y + legLength * Math.sin(angle))
          legLength += twoPi * @['spiralLengthFactor'] / angle
          pt

  p['spiderListener'] = (marker) ->
      markerSpiderfied = marker['_omsData']?
      @['unspiderfy']() unless markerSpiderfied and @['keepSpiderfied']
      if markerSpiderfied
          @trigger('mousedown', marker)
      else
          nearbyMarkerData = []
          nonNearbyMarkers = []
          nDist = @['nearbyDistance']
          pxSq = nDist * nDist
          markerPt = @llToPt(marker.lonlat)
          for m in @markers
              mPt = @llToPt(m.lonlat)
              if @ptDistanceSq(mPt, markerPt) < pxSq
                  nearbyMarkerData.push(marker: m, markerPt: mPt)
              else
                  nonNearbyMarkers.push(m)
          if nearbyMarkerData.length is 1  # 1 => the one clicked => none nearby
              @trigger('mousedown', marker)
          else
              @spiderfy(nearbyMarkerData, nonNearbyMarkers)
  
  p['makeHighlightListeners'] = (marker) ->
      highlight: => marker['_omsData'].leg.style['color'] = @['legColors']['highlighted']
      unhighlight: => marker['_omsData'].leg.style['color'] = @['legColors']['usual']

  p['markersNearMarker'] = (marker, firstOnly = no) ->
      nDist = @['nearbyDistance']
      pxSq = nDist * nDist
      markerPt = @llToPt(marker.lonlat)
      markers = []
      for m in @markers
          continue if m is marker or not m.map? or not m.isDrawn()
          mPt = @llToPt(m['_omsData']?.usualPosition ? m.lonlat)
          if @ptDistanceSq(mPt, markerPt) < pxSq
              markers.push(m)
              break if firstOnly
      markers

  p['markersNearAnyOtherMarker'] = ->  # *very* much quicker than calling markersNearMarker in a loop
      nDist = @['nearbyDistance']
      pxSq = nDist * nDist
      mData = for m in @markers
          {pt: @llToPt(m['_omsData']?.usualPosition ? m.lonlat), willSpiderfy: no}
      for m1, i1 in @markers
          continue unless m1.map? and m1.isDrawn()
          m1Data = mData[i1]
          continue if m1Data.willSpiderfy
          for m2, i2 in @markers
              continue if i2 is i1
              continue unless m2.map? and m2.isDrawn()
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
          footLl = @ptToLl(footPt)
          nearestMarkerDatum = @minExtract(markerData, (md) => @ptDistanceSq(md.markerPt, footPt))
          marker = nearestMarkerDatum.marker
          leg = new OpenLayers.Feature.Vector(new OpenLayers.Geometry.Curve([marker.lonlat, footLl]), null, {strokeColor: @['legColors']['usual'], strokeWidth: @['legWeight']})
          @map.getLayersByName('oms')[0].addFeatures(leg)
          marker['_omsData'] =
              usualPosition: marker.lonlat
              leg: leg
          unless @['legColors']['highlighted'] is @['legColors']['usual']
              mhl = @makeHighlightListeners(marker)
              marker['_omsData'].highlightListeners = mhl
              marker.events.register('mouseover', marker, mhl.highlight)
              marker.events.register('mouseout',  marker, mhl.unhighlight)
          marker.lonlat = footLl
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
              @map.getLayersByName('oms')[0].removeFeatures([marker['_omsData'].leg])
              marker.lonlat = marker['_omsData'].usualPosition unless marker is markerNotToMove
              mhl = marker['_omsData'].highlightListeners
              if mhl?
                  marker.events.unregister('mouseover', marker, mhl.highlight)
                  marker.events.unregister('mouseout',  marker, mhl.unhighlight)
              delete marker['_omsData']
              unspiderfiedMarkers.push(marker)
          else
              nonNearbyMarkers.push(marker)
      delete @unspiderfying
      delete @spiderfied
      @trigger('unspiderfy', unspiderfiedMarkers, nonNearbyMarkers)
      @  # return self, for chaining

  p['ptDistanceSq'] = (pt1, pt2) ->
      dx = pt1.x - pt2.x
      dy = pt1.y - pt2.y
      dx * dx + dy * dy

  p['ptAverage'] = (pts) ->
      sumX = sumY = 0
      for pt in pts
          sumX += pt.x; sumY += pt.y
      numPts = pts.length
      new OpenLayers.Geometry.Point(sumX / numPts, sumY / numPts)

  p['llToPt'] = (ll) ->
      pt = new OpenLayers.Geometry.Point(ll.lon, ll.lat)
      pt.transform(new OpenLayers.Projection("EPSG:4326"),
                   new OpenLayers.Projection(@map.getProjection()))
      pt
  p['ptToLl'] = (pt) ->
      ll = new OpenLayers.LonLat(pt.x, pt.y)
      ll.transform(new OpenLayers.Projection(@map.getProjection()),
                   new OpenLayers.Projection("EPSG:4326"))
      ll

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

