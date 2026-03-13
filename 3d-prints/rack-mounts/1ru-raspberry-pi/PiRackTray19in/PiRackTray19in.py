#Author: Home Ops
#Description: 1RU 19" Rack Mount for Raspberry Pi with 2.5" HDD Support

import adsk.core, adsk.fusion, traceback
import math

def run(context):
    ui = None
    try:
        app = adsk.core.Application.get()
        ui = app.userInterface
        design = app.activeProduct
        rootComp = design.rootComponent

        # Create user parameters for easy adjustment
        userParams = design.userParameters

        def addParam(name, value, units, comment):
            try:
                userParams.add(name, adsk.core.ValueInput.createByReal(value), units, comment)
            except:
                pass  # Parameter already exists

        # Rack dimensions (values in cm for Fusion)
        addParam("rack_width", 48.26, "cm", "19 inch rack standard width")
        addParam("rack_height", 4.445, "cm", "1RU height")
        addParam("rack_depth", 20.0, "cm", "Depth of mount")
        addParam("wall_thickness", 0.3, "cm", "Wall thickness")

        # Rack ears
        addParam("ear_width", 1.5875, "cm", "Mounting ear width")
        addParam("rack_hole_diameter", 0.7, "cm", "Rack mounting hole diameter")

        # Pi configuration
        addParam("pi_count", 4, "", "Number of Raspberry Pis")
        addParam("pi_width", 8.5, "cm", "Pi board width")
        addParam("pi_depth", 5.6, "cm", "Pi board depth")
        addParam("pi_hole_x", 5.8, "cm", "Pi mounting hole spacing X")
        addParam("pi_hole_y", 4.9, "cm", "Pi mounting hole spacing Y")
        addParam("pi_hole_diameter", 0.27, "cm", "Pi mounting hole diameter M2.5")
        addParam("pi_standoff_height", 0.8, "cm", "Pi standoff height")

        # HDD configuration
        addParam("hdd_width", 6.985, "cm", "2.5 inch HDD width")
        addParam("hdd_depth", 10.0, "cm", "2.5 inch HDD depth")
        addParam("hdd_hole_x", 6.172, "cm", "HDD hole spacing X")
        addParam("hdd_hole_y", 7.62, "cm", "HDD hole spacing Y")
        addParam("hdd_hole_diameter", 0.35, "cm", "HDD mounting hole diameter")

        # Split printing
        addParam("flange_width", 1.5, "cm", "Center flange width for joining")
        addParam("join_bolt_diameter", 0.45, "cm", "M4 bolt hole diameter")

        # Get parameter values
        rack_width = userParams.itemByName("rack_width").value
        rack_height = userParams.itemByName("rack_height").value
        rack_depth = userParams.itemByName("rack_depth").value
        wall_thickness = userParams.itemByName("wall_thickness").value
        ear_width = userParams.itemByName("ear_width").value
        rack_hole_diameter = userParams.itemByName("rack_hole_diameter").value
        pi_count = int(userParams.itemByName("pi_count").value)
        pi_width = userParams.itemByName("pi_width").value
        pi_depth = userParams.itemByName("pi_depth").value
        pi_hole_x = userParams.itemByName("pi_hole_x").value
        pi_hole_y = userParams.itemByName("pi_hole_y").value
        pi_hole_diameter = userParams.itemByName("pi_hole_diameter").value
        pi_standoff_height = userParams.itemByName("pi_standoff_height").value
        flange_width = userParams.itemByName("flange_width").value
        join_bolt_diameter = userParams.itemByName("join_bolt_diameter").value

        # Calculated values
        inner_width = rack_width - (2 * ear_width) - (2 * wall_thickness)
        pi_spacing = inner_width / pi_count
        center_x = rack_width / 2

        # Create sketches and bodies
        sketches = rootComp.sketches
        xyPlane = rootComp.xYConstructionPlane
        xzPlane = rootComp.xZConstructionPlane

        # ============ BASE PLATE ============
        baseSketch = sketches.add(xyPlane)
        baseLines = baseSketch.sketchCurves.sketchLines

        # Base plate rectangle
        baseLines.addTwoPointRectangle(
            adsk.core.Point3D.create(ear_width, 0, 0),
            adsk.core.Point3D.create(rack_width - ear_width, rack_depth, 0)
        )

        # Extrude base plate
        baseProfile = baseSketch.profiles.item(0)
        extrudes = rootComp.features.extrudeFeatures
        extInput = extrudes.createInput(baseProfile, adsk.fusion.FeatureOperations.NewBodyFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(wall_thickness))
        baseExtrude = extrudes.add(extInput)

        # ============ SIDE WALLS ============
        # Left wall
        leftWallSketch = sketches.add(xyPlane)
        leftWallLines = leftWallSketch.sketchCurves.sketchLines
        leftWallLines.addTwoPointRectangle(
            adsk.core.Point3D.create(ear_width, 0, 0),
            adsk.core.Point3D.create(ear_width + wall_thickness, rack_depth, 0)
        )
        leftWallProfile = leftWallSketch.profiles.item(0)
        extInput = extrudes.createInput(leftWallProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
        extrudes.add(extInput)

        # Right wall
        rightWallSketch = sketches.add(xyPlane)
        rightWallLines = rightWallSketch.sketchCurves.sketchLines
        rightWallLines.addTwoPointRectangle(
            adsk.core.Point3D.create(rack_width - ear_width - wall_thickness, 0, 0),
            adsk.core.Point3D.create(rack_width - ear_width, rack_depth, 0)
        )
        rightWallProfile = rightWallSketch.profiles.item(0)
        extInput = extrudes.createInput(rightWallProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
        extrudes.add(extInput)

        # ============ FRONT LIP ============
        frontLipSketch = sketches.add(xyPlane)
        frontLipLines = frontLipSketch.sketchCurves.sketchLines
        frontLipLines.addTwoPointRectangle(
            adsk.core.Point3D.create(ear_width, 0, 0),
            adsk.core.Point3D.create(rack_width - ear_width, wall_thickness, 0)
        )
        frontLipProfile = frontLipSketch.profiles.item(0)
        extInput = extrudes.createInput(frontLipProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
        extrudes.add(extInput)

        # ============ REAR LIP (lower for cables) ============
        rearLipSketch = sketches.add(xyPlane)
        rearLipLines = rearLipSketch.sketchCurves.sketchLines
        rearLipLines.addTwoPointRectangle(
            adsk.core.Point3D.create(ear_width, rack_depth - wall_thickness, 0),
            adsk.core.Point3D.create(rack_width - ear_width, rack_depth, 0)
        )
        rearLipProfile = rearLipSketch.profiles.item(0)
        extInput = extrudes.createInput(rearLipProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height * 0.5))
        extrudes.add(extInput)

        # ============ RACK EARS ============
        # Left ear
        leftEarSketch = sketches.add(xyPlane)
        leftEarLines = leftEarSketch.sketchCurves.sketchLines
        leftEarLines.addTwoPointRectangle(
            adsk.core.Point3D.create(0, 0, 0),
            adsk.core.Point3D.create(ear_width, wall_thickness, 0)
        )
        leftEarProfile = leftEarSketch.profiles.item(0)
        extInput = extrudes.createInput(leftEarProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
        extrudes.add(extInput)

        # Right ear
        rightEarSketch = sketches.add(xyPlane)
        rightEarLines = rightEarSketch.sketchCurves.sketchLines
        rightEarLines.addTwoPointRectangle(
            adsk.core.Point3D.create(rack_width - ear_width, 0, 0),
            adsk.core.Point3D.create(rack_width, wall_thickness, 0)
        )
        rightEarProfile = rightEarSketch.profiles.item(0)
        extInput = extrudes.createInput(rightEarProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
        extrudes.add(extInput)

        # ============ CENTER FLANGE (for split printing) ============
        flangeSketch = sketches.add(xyPlane)
        flangeLines = flangeSketch.sketchCurves.sketchLines
        flangeLines.addTwoPointRectangle(
            adsk.core.Point3D.create(center_x - flange_width/2, 0, 0),
            adsk.core.Point3D.create(center_x + flange_width/2, rack_depth, 0)
        )
        flangeProfile = flangeSketch.profiles.item(0)
        extInput = extrudes.createInput(flangeProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height * 0.7))
        extrudes.add(extInput)

        # ============ PI STANDOFFS ============
        for i in range(pi_count):
            x_offset = ear_width + wall_thickness + (pi_spacing * i) + (pi_spacing - pi_width) / 2
            y_offset = (rack_depth - pi_depth) / 2

            standoff_positions = [
                [0, 0],
                [pi_hole_x, 0],
                [0, pi_hole_y],
                [pi_hole_x, pi_hole_y]
            ]

            for pos in standoff_positions:
                standoff_x = x_offset + (pi_width - pi_hole_x) / 2 + pos[0]
                standoff_y = y_offset + (pi_depth - pi_hole_y) / 2 + pos[1]

                # Create standoff sketch on top of base
                standoffPlane = adsk.core.Plane.create(
                    adsk.core.Point3D.create(0, 0, wall_thickness),
                    adsk.core.Vector3D.create(0, 0, 1)
                )
                constructionPlanes = rootComp.constructionPlanes
                planeInput = constructionPlanes.createInput()
                planeInput.setByOffset(xyPlane, adsk.core.ValueInput.createByReal(wall_thickness))
                standoffConstructionPlane = constructionPlanes.add(planeInput)

                standoffSketch = sketches.add(standoffConstructionPlane)
                standoffCircles = standoffSketch.sketchCurves.sketchCircles
                standoffCircles.addByCenterRadius(
                    adsk.core.Point3D.create(standoff_x, standoff_y, 0),
                    0.3  # 6mm diameter standoff
                )

                standoffProfile = standoffSketch.profiles.item(0)
                extInput = extrudes.createInput(standoffProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
                extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(pi_standoff_height))
                extrudes.add(extInput)

        # ============ RACK MOUNTING HOLES ============
        holeFeats = rootComp.features.holeFeatures

        hole_z_positions = [rack_height * 0.25, rack_height * 0.5, rack_height * 0.75]

        for z in hole_z_positions:
            # Create construction plane at hole height
            planeInput = constructionPlanes.createInput()
            planeInput.setByOffset(xyPlane, adsk.core.ValueInput.createByReal(z))
            holePlane = constructionPlanes.add(planeInput)

            # Left ear hole
            leftHoleSketch = sketches.add(holePlane)
            leftHolePoint = leftHoleSketch.sketchPoints.add(
                adsk.core.Point3D.create(ear_width / 2, wall_thickness / 2, 0)
            )

            # Right ear hole
            rightHoleSketch = sketches.add(holePlane)
            rightHolePoint = rightHoleSketch.sketchPoints.add(
                adsk.core.Point3D.create(rack_width - ear_width / 2, wall_thickness / 2, 0)
            )

        # ============ CENTER FLANGE BOLT HOLES ============
        flange_height = rack_height * 0.7
        bolt_spacing = (rack_depth - 4.0) / 2  # 3 bolts

        for i in range(3):
            y_pos = 2.0 + (i * bolt_spacing)

            # Create plane for bolt hole
            planeInput = constructionPlanes.createInput()
            planeInput.setByOffset(xyPlane, adsk.core.ValueInput.createByReal(flange_height / 2))
            boltPlane = constructionPlanes.add(planeInput)

            boltSketch = sketches.add(boltPlane)
            boltCircles = boltSketch.sketchCurves.sketchCircles
            boltCircles.addByCenterRadius(
                adsk.core.Point3D.create(center_x, y_pos, 0),
                join_bolt_diameter / 2
            )

        ui.messageBox('1RU Pi Rack Mount created!\n\nTo split for printing:\n1. Use "Combine > Cut" with a plane at the center\n2. Export each half as separate STL files\n\nUser parameters can be modified in "Modify > Change Parameters"')

    except:
        if ui:
            ui.messageBox('Failed:\n{}'.format(traceback.format_exc()))
