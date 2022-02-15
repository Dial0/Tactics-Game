package main
import rl "vendor:raylib"

import "core:math"
import "core:math/linalg"
import "core:log"
import "core:bufio"
import "core:io"
import "core:strings"
import "core:strconv"
import "core:mem"

check_bounds :: proc(point:[2]f32,bounds:struct{bl:[2]f32,tr:[2]f32}) -> (inbounds:bool) {
	log.infof("point: %v\n",point);
	log.infof("bounds: %v\n",bounds);
	inbounds = false
	if point.x > bounds.bl.x && point.y > bounds.bl.y && point.x < bounds.tr.x && point.y < bounds.tr.y {
		inbounds = true
	}
	log.infof("check: %v\n",inbounds);
	return
}



order_quad :: proc(quad_points:[4]rl.Vector3) ->(ordered_points:[4]rl.Vector3){
	m:rl.Vector3

	m.x = (quad_points[0].x + quad_points[1].x + quad_points[2].x + quad_points[3].x) / 4
	m.y = (quad_points[0].y + quad_points[1].y + quad_points[2].y + quad_points[3].y) / 4
	m.z = (quad_points[0].z + quad_points[1].z + quad_points[2].z + quad_points[3].z) / 4
	unordered_points : [dynamic]rl.Vector3
	for i := 1; i < 4; i += 1 {
		append(&unordered_points,quad_points[i])
	}

	ordered_points[0] = quad_points[0]
	for point,i in unordered_points{

		det := (ordered_points[0].x - m.x) * (point.z - m.z) - (point.x - m.x) * (ordered_points[0].z - m.z)

		if (det > 0.0001 || det < -0.0001){
			ordered_points[1] = point
			unordered_remove(&unordered_points,i)
			break
		}
	}

	for point,i in unordered_points{
		det := (ordered_points[1].x - m.x) * (point.z - m.z) - (point.x - m.x) * (ordered_points[1].z - m.z)
		if (det > 0.0001 || det < -0.0001){
			ordered_points[2] = point
			unordered_remove(&unordered_points,i)
			break
		}
	}

	ordered_points[3] = unordered_points[0]
	delete(unordered_points)
	return
}

Map_Node :: struct{
	quad: [4]u16,
	neighbors: [dynamic]u16,
}


not_in_nodes::proc(node_id:u16,visited_nodes:^[dynamic]u16)->bool{
	add := true
	for visited_node in visited_nodes{
		if node_id == visited_node{
			add = false
		}
	}
	return add
}

recursive_get_neighbors_with_depth :: proc(depth: u16, max_depth: u16, node_id:u16, map_nodes:^[dynamic]Map_Node,visited_nodes:^[dynamic]u16,visited_node_depths:^[dynamic]u16){
	node := map_nodes[node_id]
	if depth >= max_depth{
		return
	}

	add := true
	for visited_node,i in visited_nodes{
		if node_id == visited_node{
			add = false
			if visited_node_depths[i] > depth{
				visited_node_depths[i] = depth
			}
		}
	}

	if add{
		append(visited_nodes,node_id)
		append(visited_node_depths,u16(depth))
	}

	for neighbor in node.neighbors{
		recursive_get_neighbors_with_depth(depth+1,max_depth,neighbor,map_nodes,visited_nodes,visited_node_depths)
	}
	return
}


recursive_get_neighbors :: proc(depth: i16, max_depth: i16, node_id:u16, map_nodes:^[dynamic]Map_Node,visited_nodes:^[dynamic]u16){
	node := map_nodes[node_id]
	if depth >= max_depth{
		return
	}

	if not_in_nodes(node_id,visited_nodes){
		append(visited_nodes,node_id)
	}

	for neighbor in node.neighbors{
		recursive_get_neighbors(depth+1,max_depth,neighbor,map_nodes,visited_nodes)
	}
	return
}


character :: struct {
	node : u16,
	moveable : bool,
}

main :: proc() {
	context.logger = log.create_console_logger();

	rl.InitWindow(1280, 720, "Raylib Game")
	rl.SetWindowState({.VSYNC_HINT,.WINDOW_RESIZABLE})




	camera : rl.Camera3D

	camera.position = {0.0, 15.0,-20.0}
	camera.target = {-15.0,0.0,0.0}
	camera.up = {0.0,1.6,0.0}
	camera.fovy = 45.0
	camera.projection = .PERSPECTIVE
	shader := rl.LoadShader("", "base.fs");

	m_tower := rl.LoadModel("level.glb")
	m_character := rl.LoadModel("character.glb")
	map_bounds : struct{bl:[2]f32,tr:[2]f32} = {{-17,-17},{5,17}}
	read_bytes : u32
	map_data := rl.LoadFileData("map.node_tree",&read_bytes)
	map_string_data := string(map_data[:read_bytes])
	map_text_data := strings.split(map_string_data,"Nodes:")
	
	vertex_lines := strings.split(map_text_data[0],"\n")

	node_vertices : [dynamic]rl.Vector3

	for line in vertex_lines {
		if(len(line)>0){
			r_line,_ := strings.replace(line,"[","",-1)
			r_line,_ = strings.replace(r_line,"]","",-1)
			points := strings.split(string(r_line),", ")
			x := f32(strconv.atof(points[0]))
			y := f32(strconv.atof(points[1]))
			z := f32(strconv.atof(points[2]))
			point := rl.Vector3({x,z,y*-1})
			append(&node_vertices,point)
		}
	}

	log.infof("node_vertices: %v\n",map_text_data[1])

	map_nodes : [dynamic]Map_Node
	
	for line in strings.split(map_text_data[1],"\n"){
		if(len(line)>1){
			node_data := strings.split(line,"'connected nodes':")
			quad_data := strings.cut(node_data[0], len("{'vertices': ["), len(node_data[0])-len("{'vertices': [")-3)
			quad_indices := strings.split(quad_data,", ")
			temp_node : Map_Node
			for vert_index,i in quad_indices {
				temp_node.quad[i] = u16(strconv.atoi(vert_index))
			}

			neighbor_data := node_data[1]

			for rem_rune in "[]} "{
				temp : =[1]u8{u8(rem_rune)}
				neighbor_data,_ = strings.remove_all(neighbor_data,string(temp[:]))
			}
			
			for neighbor in strings.split(neighbor_data,","){
				append(&temp_node.neighbors,u16(strconv.atoi(neighbor)))
			}

			append(&map_nodes,temp_node)
		}

	}


	

	//t_tower := rl.LoadTexture("turret_diffuse.png")
	m_character.materials[1].shader = shader
	m_tower.materials[1].shader = shader

	angle := f32(0.0)
	z_angle := f32(rl.PI/4)

	base_camera_z_radius := f32(20.0)

	camera_z_radius := math.sin(z_angle) * base_camera_z_radius
	camera_z := math.cos(z_angle) * base_camera_z_radius

	x := f32(math.sin(angle) * camera_z_radius)
	y := f32(math.cos(angle) * camera_z_radius)
	camera.position = {x, camera_z,y}
	camera.position += camera.target

	towerPos : rl.Vector3 = {0.0,0.0,0.0}

	active_node := i16(-1)

	in_range_neighbors:[dynamic]u16
	in_range_neighbors_depth:[dynamic]u16


	selected_character := u8(0)

	characters:[dynamic]character
	append(&characters,character{21,true})
	append(&characters,character{22,true})
	append(&characters,character{23,true})

	for !rl.WindowShouldClose() {


		if rl.IsMouseButtonDown(.RIGHT){
			mouse_delta := rl.GetMouseDelta()

			m_delta_x := -mouse_delta.x
			m_delta_y := -mouse_delta.y
			angle += m_delta_x /100;
			z_angle += m_delta_y /100;

			z_angle = linalg.clamp(z_angle, rl.PI/4-rl.PI/8,rl.PI/4 + rl.PI/8)

			camera_z_radius := math.sin(z_angle) * base_camera_z_radius
			camera_z := math.cos(z_angle) * base_camera_z_radius
			x = f32(math.sin(angle) * camera_z_radius)
			y = f32(math.cos(angle) * camera_z_radius)
			camera.position = {x, camera_z,y} +  camera.target


		}

		left_click: if rl.IsMouseButtonPressed(.LEFT){



			ray := rl.GetMouseRay(rl.GetMousePosition(), camera)

			hit_node := i16(-1)

			for node,i in map_nodes{
				quad_points := [4]rl.Vector3{node_vertices[node.quad[0]],node_vertices[node.quad[1]],node_vertices[node.quad[2]],node_vertices[node.quad[3]]}
				order_quad_points := order_quad(quad_points)
				if rl.GetRayCollisionQuad(ray,order_quad_points[0],order_quad_points[1],order_quad_points[2],order_quad_points[3]).hit{
					hit_node = i16(i)
					break
				}
			}

			if hit_node == -1 {
				break left_click
			}

			//if node contains a player controller character switch to that character
			for character,i in characters {
				if character.node == u16(hit_node) {

					selected_character = u8(i)

					active_node = i16(character.node)

					clear(&in_range_neighbors)
					clear(&in_range_neighbors_depth)
					append(&in_range_neighbors,u16(active_node))
					append(&in_range_neighbors_depth,0)
					if character.moveable {
						recursive_get_neighbors_with_depth(0,5,u16(active_node),&map_nodes,&in_range_neighbors,&in_range_neighbors_depth)
					}
					break left_click
				}
			}

			if characters[selected_character].moveable == false{
				break left_click
			}

			//otherwise try to move the selected character
			for node in in_range_neighbors {
				if u16(hit_node) == node {
					characters[selected_character].node = u16(hit_node)
					active_node = i16(characters[selected_character].node)
					clear(&in_range_neighbors)
					clear(&in_range_neighbors_depth)
					append(&in_range_neighbors,u16(active_node))
					append(&in_range_neighbors_depth,0)
					characters[selected_character].moveable = false
				}
			}

		}


		if rl.IsKeyDown(.W){
			cam_dir_2D := linalg.normalize(camera.target.xz - camera.position.xz)
			if check_bounds(camera.target.xz+cam_dir_2D,map_bounds){
				camera.target.xz += cam_dir_2D
				camera.position.xz += cam_dir_2D
			}
		}
		if rl.IsKeyDown(.S){
			cam_dir_2D := linalg.normalize(camera.target.xz - camera.position.xz)
			if check_bounds(camera.target.xz-cam_dir_2D,map_bounds){
				camera.target.xz -= cam_dir_2D
				camera.position.xz -= cam_dir_2D
			}
		}
		if rl.IsKeyDown(.A){
			cam_dir_2D := linalg.normalize(camera.target.xz - camera.position.xz)
			cam_dir_2D.x *= -1
			if check_bounds(camera.target.xz+cam_dir_2D.yx,map_bounds){
				camera.target.xz += cam_dir_2D.yx
				camera.position.xz += cam_dir_2D.yx
			}
		}
		if rl.IsKeyDown(.D){
			cam_dir_2D := linalg.normalize(camera.target.xz - camera.position.xz)
			cam_dir_2D.y *= -1
			if check_bounds(camera.target.xz+cam_dir_2D.yx,map_bounds){
				camera.target.xz += cam_dir_2D.yx
				camera.position.xz += cam_dir_2D.yx
			}

		}


		if rl.IsKeyPressed(.E){
			for character,i in characters {
				characters[i].moveable = true
			}
			node := characters[selected_character].node
			recursive_get_neighbors_with_depth(0,5,u16(node),&map_nodes,&in_range_neighbors,&in_range_neighbors_depth)
		}






		//RENDER
		

		rl.BeginDrawing()
			rl.rlDisableBackfaceCulling()
			rl.ClearBackground({9,88,138,1.0})
			rl.BeginMode3D(camera)
				rl.DrawModel(m_tower,towerPos,1.0,rl.WHITE)


				for neighbor,i in in_range_neighbors{
					node := map_nodes[neighbor]
					quad_points := [4]rl.Vector3{node_vertices[node.quad[0]],node_vertices[node.quad[1]],node_vertices[node.quad[2]],node_vertices[node.quad[3]]}
					ordered_points := order_quad(quad_points)

					if in_range_neighbors_depth[i] == 0 {
						rl.DrawTriangle3D(ordered_points[0],ordered_points[1],ordered_points[2],rl.BLUE)
						rl.DrawTriangle3D(ordered_points[2],ordered_points[3],ordered_points[0],rl.BLUE)
					}

					if in_range_neighbors_depth[i] == 1 {
						rl.DrawTriangle3D(ordered_points[0],ordered_points[1],ordered_points[2],rl.GREEN)
						rl.DrawTriangle3D(ordered_points[2],ordered_points[3],ordered_points[0],rl.GREEN)
					}

					if in_range_neighbors_depth[i] == 2 {
						rl.DrawTriangle3D(ordered_points[0],ordered_points[1],ordered_points[2],rl.YELLOW)
						rl.DrawTriangle3D(ordered_points[2],ordered_points[3],ordered_points[0],rl.YELLOW)
					}

					if in_range_neighbors_depth[i] == 3 {
						rl.DrawTriangle3D(ordered_points[0],ordered_points[1],ordered_points[2],rl.ORANGE)
						rl.DrawTriangle3D(ordered_points[2],ordered_points[3],ordered_points[0],rl.ORANGE)
					}

					if in_range_neighbors_depth[i] == 4 {
						rl.DrawTriangle3D(ordered_points[0],ordered_points[1],ordered_points[2],rl.RED)
						rl.DrawTriangle3D(ordered_points[2],ordered_points[3],ordered_points[0],rl.RED)
					}

				}

				for character in characters{
					node := map_nodes[character.node]
					quad_points := [4]rl.Vector3{node_vertices[node.quad[0]],node_vertices[node.quad[1]],node_vertices[node.quad[2]],node_vertices[node.quad[3]]}

					m:rl.Vector3

					m.x = (quad_points[0].x + quad_points[1].x + quad_points[2].x + quad_points[3].x) / 4
					m.y = (quad_points[0].y + quad_points[1].y + quad_points[2].y + quad_points[3].y) / 4
					m.z = (quad_points[0].z + quad_points[1].z + quad_points[2].z + quad_points[3].z) / 4

					ordered_points := order_quad(quad_points)

					rl.DrawModel(m_character,m,1.0,rl.WHITE)
				}

			rl.EndMode3D()

			rl.DrawText(rl.TextFormat("Press E to end turn"),0,0,24,rl.RED)
		rl.EndDrawing()
	}

	rl.CloseWindow()
}