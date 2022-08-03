globals [
  growth-phase?
  destroy-phase?
  network-failed?
  network-failed-tick1?
  network-failed-tick2?
  component-list;; list of specific network nodes
  network-list;;list of lists of all networks
  ordered-network-list
  num-networks
  num-nodes
  newest-node
  tmp-node
  needed-connections
  num-links
  highest-links
  max-num-links
  max-num-nodes
  failure-largest-num-nodes
  failure-total-num-nodes
  transition-ticks
  size-1st-network
  size-2nd-network
  size-3rd-network
  size-other-networks

]

turtles-own [
  explored?;; this is used to mark turtles we have already visited
  fitness;;refers to attachment preference during growth phase and death preference during destroy phase
  num-neighbors
]
;;;;;;;;;;;;;;;;;;;;;;;;
;;; Setup Procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  reset-ticks
  set-default-shape turtles "circle"
  ask patches [set pcolor 101]
  set num-nodes 0
  make-node
  set num-nodes count turtles
  make-node
  set growth-phase? true
  set destroy-phase? false
  set network-failed? false
end


;;;;;;;;;;;;;;;;;;;;;;;
;;; Main Procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;

to go
  if layout? [ layout ]
  set num-nodes count turtles
  ;stay in growth phase or transition to destroy phase
  if (growth-phase?) and (num-nodes >= node-num-max) [
    transition-from-growth-to-destroy
  ]
  if growth-phase? [ do-growth-phase ]
  if destroy-phase? [ do-destroy-phase ]

  ;end program before all nodes are dead
  if num-nodes < 2 [
    display
    user-message "There are no more nodes to destroy. Using 'go' before resetting will crash the simulation."
    stop
  ]
  tick
end


;;;;;;;;;;;;;;;;;;;;
;;; Growth Phase ;;;
;;;;;;;;;;;;;;;;;;;;

to do-growth-phase
;; new edge is yellow, old edges are gray
    ask links [ set color gray ]
    make-node
    update-fitness
end

;; used for creating a new node and making connections during growth phase
to make-node

  set needed-connections num-connections-per-node
  if chance-extra-connection >= random-float 1 [
    set needed-connections (needed-connections + 1)
  ]
  create-turtles 1
  [
    set color green + 1

  ]
  ;get node that was just made
  set newest-node turtle max [who] of turtles

  ; create 0 or 1 links if network is not big enough to support 'num-connections-per-node'
  ifelse num-nodes < needed-connections [
    if num-nodes != 0 [
      connect-nodes (newest-node) (one-of turtles)
    ]
  ]
  ; create enough links on new node to support 'num-connections-per-node'
  [
    let tmp 0
    loop [
      if tmp = needed-connections [ stop ]
      set tmp (tmp + 1)
      ;ensure other node isn't used already and meets attachment fitness requirements
      set tmp-node one-of turtles with [ (self != newest-node) and (not link-neighbor? newest-node) and (fitness >= random-float 1) ]
      ;force random connection in the rare chance that no nodes meet attachment fitness requirements
      if tmp-node = nobody [
        set tmp-node one-of turtles with [ (self != newest-node) and (not link-neighbor? newest-node) ]
      ]
      connect-nodes (newest-node) (tmp-node)
    ]
  ]
end

to connect-nodes [new-node old-node]
  ask new-node [
    ifelse link-neighbor? old-node or new-node = old-node
    ;; if there's already an edge there, then go back
    ;; and pick new turtles
    [ connect-nodes (new-node) (one-of turtles) ]
    ;; else, go ahead and make it
    [ create-link-with old-node [ set color yellow ]
      move-to old-node
      fd 8
    ]
  ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Transition Procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to transition-from-growth-to-destroy
  set growth-phase? false
  set destroy-phase? true
  set transition-ticks ticks
  ;collect some statistics to display
  set max-num-links count links
  set max-num-nodes count turtles
  ask patches [set pcolor black]
end


;;;;;;;;;;;;;;;;;;;;;
;;; Destroy Phase ;;;
;;;;;;;;;;;;;;;;;;;;;

to do-destroy-phase
  ask turtles [ set color red ]
  set tmp-node one-of turtles with [fitness <= random-float 1 ]
  ifelse tmp-node != nobody [
    ask tmp-node [die]
  ][
    ask one-of turtles [die]
  ]
  set num-nodes count turtles

  find-all-components
  set ordered-network-list sort-by larger-length network-list
  color-networks

  ;;check if network has failed based on user input and percentage of network in largest
  if (not network-failed?) and ((size-1st-network / num-nodes) <= failure-benchmark) [
    set network-failed? true
    set network-failed-tick1? true ;; for plotting vertical line on % graph
    set network-failed-tick2? true ;; for plotting vertical line on # graph
    set failure-largest-num-nodes size-1st-network
    set failure-total-num-nodes num-nodes
    ;set failure-larg-num-links count
  ]
  update-fitness
  wait destruction-delay
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Attachment/Death Fitness ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;refers to attachment preference during growth phase and death resilience during destroy phase
to update-fitness
  set num-links count links


  set highest-links 0

  ask turtles [
    set num-neighbors count link-neighbors
    if num-neighbors > highest-links [
      set highest-links num-neighbors
    ]
  ]
  if highest-links = 0 [ set highest-links 1 ]

  ask turtles [
    ;num-neighbors / highest-links ;0 to 1

    ifelse growth-phase? [
      set fitness ((1 - attach-preference-bias-factor) + ((num-neighbors / highest-links) * (attach-preference-bias-factor)))
      if attach-preference = "Weakly Linked Nodes" [
        set fitness (1 - fitness)
      ]
    ] [;;otherwise destroy-phase
      set fitness ((1 - death-preference-bias-factor) + ((num-neighbors / highest-links) * (death-preference-bias-factor)))
      if death-preference = "Highly Linked Nodes" [
        set fitness (1 - fitness)
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Network Exploration ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; to find all the connected components in the network, their sizes and starting turtles
;; and put them into a list of lists
to find-all-components
  ask turtles [ set explored? false ]
  set network-list []
  ;; keep exploring till all turtles get explored

  loop
  [
    ;; pick a node that has not yet been explored
    let start one-of turtles with [ not explored? ]
    if start = nobody [ stop ]
    ;; reset the number of turtles found to 0
    ;; this variable is updated each time we explore an
    ;; unexplored node.
    set component-list []
    ;; at this stage, we recolor everything to light gray
    ask start [ explore (red) ]
    ;; the explore procedure updates the component-size variable.
    ;; so check, have we found a new giant component?


    set network-list insert-item 0 network-list component-list
  ]
end

;;used for reordering list of lists of current networks
to-report larger-length [a b]
  report (length a) > (length b)
end


;; Finds all turtles reachable from this node (and recolors them)
to explore [new-color]  ;; node procedure
  if explored? [ stop ]
  set explored? true
  set component-list insert-item 0 component-list who

  ;; color the node
  set color new-color
  ask link-neighbors [ explore new-color ]
end

;;color the networks based on 1st, 2nd, and 3rd largest network (all others already red)
to color-networks
  set size-1st-network 0
  set size-2nd-network 0
  set size-3rd-network 0
  set num-networks length ordered-network-list
  if num-networks >= 1 [
    set size-1st-network (length item 0 ordered-network-list)
    foreach item 0 ordered-network-list [
      x -> ask turtle x [set color green ]
    ]
  ]
  if num-networks >= 2 [
    set size-2nd-network (length item 1 ordered-network-list)
    foreach item 1 ordered-network-list [
      x -> ask turtle x [set color yellow ]
    ]
  ]
  if num-networks >= 3 [
    set size-3rd-network (length item 2 ordered-network-list)
    foreach item 2 ordered-network-list [
      x -> ask turtle x [set color orange ]
    ]
  ]
  set size-other-networks (num-nodes - size-1st-network - size-2nd-network - size-3rd-network)
end

;;;;;;;;;;;;;;;
;;; Utility ;;;
;;;;;;;;;;;;;;;

;; resize-nodes, change back and forth from size based on degree to a size of 1
to resize-nodes
  ifelse all? turtles [size <= 1]
  [
    ;; a node is a circle with diameter determined by
    ;; the SIZE variable; using SQRT makes the circle's
    ;; area proportional to its degree
    ask turtles [ set size sqrt count link-neighbors ]
  ]
  [
    ask turtles [ set size 1 ]
  ]
end

to layout
  ;; the number 3 here is arbitrary; more repetitions slows down the
  ;; model, but too few gives poor layouts
  repeat 3 [
    ;; the more turtles we have to fit into the same amount of space,
    ;; the smaller the inputs to layout-spring we'll need to use
    let factor sqrt count turtles
    ;; numbers here are arbitrarily chosen for pleasing appearance
    ;layout-spring turtles links (1 / factor) (7 / factor) (1 / factor)
    layout-spring turtles links (1 / factor) (7 / factor) (6 / factor)
    display  ;; for smooth animation
  ]
  ;; don't bump the edges of the world
  let x-offset max [xcor] of turtles + min [xcor] of turtles
  let y-offset max [ycor] of turtles + min [ycor] of turtles
  ;; big jumps look funny, so only adjust a little each time
  set x-offset limit-magnitude x-offset 0.1
  set y-offset limit-magnitude y-offset 0.1
  ask turtles [ setxy (xcor - x-offset / 2) (ycor - y-offset / 2) ]
end

to-report limit-magnitude [number limit]
  if number > limit [ report limit ]
  if number < (- limit) [ report (- limit) ]
  report number
end
@#$#@#$#@
GRAPHICS-WINDOW
215
10
703
499
-1
-1
5.275
1
10
1
1
1
0
0
0
1
-45
45
-45
45
1
1
1
ticks
60.0

BUTTON
5
10
60
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
155
10
210
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
95
10
150
43
go-once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SWITCH
118
50
210
83
layout?
layout?
0
1
-1000

MONITOR
721
240
788
285
# of Nodes
num-nodes
0
1
11

BUTTON
5
50
77
84
resize nodes
resize-nodes
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
5
105
210
138
node-num-max
node-num-max
5
1000
1000.0
5
1
NIL
HORIZONTAL

SLIDER
5
240
210
273
attach-preference-bias-factor
attach-preference-bias-factor
0
1
1.0
.01
1
NIL
HORIZONTAL

SLIDER
5
145
210
178
num-connections-per-node
num-connections-per-node
1
5
4.0
1
1
NIL
HORIZONTAL

SLIDER
5
445
210
478
destruction-delay
destruction-delay
.001
1
0.001
.001
1
seconds
HORIZONTAL

SLIDER
5
185
210
218
chance-extra-connection
chance-extra-connection
0
1
0.0
.01
1
NIL
HORIZONTAL

PLOT
710
10
1104
236
% Nodes in Each Network
time
% of nodes
0.0
10.0
0.0
100.0
true
true
"" ""
PENS
"Largest" 1.0 0 -15040220 true "" "if destroy-phase? [\nplot (100 * (length item 0 ordered-network-list)) / (count turtles)\n]"
"2nd Largest" 1.0 0 -1184463 true "" "if destroy-phase? [\n  ifelse length ordered-network-list > 2 [\n    plot (100 * (length item 1 ordered-network-list)) / (count turtles)\n  ][\n    plot 0\n  ]\n]"
"3rd Largest" 1.0 0 -955883 true "" "if destroy-phase? [\n  ifelse length ordered-network-list > 3 [\n    plot (100 * (length item 2 ordered-network-list)) / (count turtles)\n  ][\n    plot 0\n  ]\n]"
"All Others" 1.0 0 -8053223 true "" "if destroy-phase? [\n  ifelse length ordered-network-list > 3 [\n    plot (100 - (100 * (length item 0 ordered-network-list) + (length item 1 ordered-network-list) + (length item 2 ordered-network-list)) / (count turtles))\n  ][\n    plot 0\n  ]\n]"
"Failure" 1.0 0 -16777216 true "" "if network-failed-tick1? [\n  plot-pen-up\n  plotxy (ticks - transition-ticks - 1) 0 \n  plot-pen-down\n  plotxy (ticks - transition-ticks - 1) plot-y-max \n  set network-failed-tick1? false\n]"

PLOT
710
290
1102
500
# Nodes in Each Network
Time
# of Nodes
0.0
10.0
0.0
100.0
true
true
"" ""
PENS
"Largest" 1.0 0 -15040220 true "" "if destroy-phase? [ plot size-1st-network]"
"2nd Largest" 1.0 0 -1184463 true "" "if destroy-phase? [\n  ifelse num-networks > 2 [\n    plot size-2nd-network\n  ][\n    plot 0\n  ]\n]"
"3rd Largest" 1.0 0 -955883 true "" "if destroy-phase? [\n  ifelse num-networks > 3 [\n    plot size-3rd-network\n  ][\n    plot 0\n  ]\n]"
"All Others" 1.0 0 -8053223 true "" "if destroy-phase? [\n  ifelse num-networks > 3 [\n    plot (num-nodes - size-1st-network - size-2nd-network - size-3rd-network)\n  ][\n    plot 0\n  ]\n]"
"Failure" 1.0 0 -16777216 true "" "if network-failed-tick2? [\n  plot-pen-up\n  plotxy (ticks - transition-ticks - 1) 0 \n  plot-pen-down\n  plotxy (ticks - transition-ticks - 1) plot-y-max \n  set network-failed-tick2? false\n]"

MONITOR
866
240
974
285
% Nodes in Largest
100 * size-1st-network / num-nodes
6
1
11

CHOOSER
5
392
210
437
death-preference
death-preference
"Highly Linked Nodes" "Weakly Linked Nodes"
0

SLIDER
17
571
192
604
failure-benchmark
failure-benchmark
.2
.99
0.85
.01
1
NIL
HORIZONTAL

MONITOR
45
520
167
565
% in Largest to Fail
failure-benchmark * 100
0
1
11

MONITOR
455
570
575
615
Total Links Created
max-num-links
0
1
11

MONITOR
455
520
575
565
Total Nodes Created
max-num-nodes
0
1
11

MONITOR
810
520
909
565
Largest Network
failure-largest-num-nodes
0
1
11

MONITOR
700
570
802
615
Total
failure-total-num-nodes
0
1
11

MONITOR
810
570
910
615
All Other Networks
failure-total-num-nodes - failure-largest-num-nodes
0
1
11

MONITOR
945
520
1103
565
# Nodes Destroyed at Failure
max-num-nodes - failure-total-num-nodes
0
1
11

MONITOR
945
570
1104
615
% Nodes Destroyed at Failure
100 * (1 - (failure-total-num-nodes / max-num-nodes))
2
1
11

MONITOR
791
240
861
285
# of Links
num-links
0
1
11

TEXTBOX
707
535
815
553
# Nodes at Failure
11
0.0
1

TEXTBOX
582
536
690
608
Failure Statistics:\n(Based on when \nlargest network\nbelow failure-benchmark)
11
0.0
1

TEXTBOX
341
542
393
571
Current \nStatistics:
11
0.0
1

SLIDER
5
350
210
383
death-preference-bias-factor
death-preference-bias-factor
0
1
1.0
.01
1
NIL
HORIZONTAL

CHOOSER
5
280
210
325
attach-preference
attach-preference
"Highly Linked Nodes" "Weakly Linked Nodes"
0

TEXTBOX
20
90
164
108
Growth Phase Parameters:
11
0.0
1

TEXTBOX
20
335
167
354
Destroy Phase Parameters:
11
0.0
1

MONITOR
978
240
1094
285
% Nodes in Largest 3
100 * (size-1st-network + size-2nd-network + size-3rd-network) / num-nodes
6
1
11

@#$#@#$#@
## CREDITS AND REFERENCES

This model is based on heavily modified versions of:


* Wilensky, U. (2005).  NetLogo Preferential Attachment model.  http://ccl.northwestern.edu/netlogo/models/PreferentialAttachment.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.


* Wilensky, U. (2005).  NetLogo Giant Component model.  http://ccl.northwestern.edu/netlogo/models/GiantComponent.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.2
@#$#@#$#@
set layout? false
set plot? false
setup repeat 300 [ go ]
repeat 100 [ layout ]
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
