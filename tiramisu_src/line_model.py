import psycopg2
import sys

def get_state(name, c):
	c.execute("select * from tiramisu_state where vm_name=%s", (name,))
	state = c.fetchone()
	latency_vm 	= state[1]
	iops_vm 	= state[2]
	latency_hdd	= state[3]
	iops_hdd 	= state[4]
	latency_ssd	= state[5]
	iops_ssd 	= state[6]

	return {	"latency_vm"	: latency_vm,
				"iops_vm"		: iops_vm,
				"latency_hdd"	: latency_hdd,
				"iops_hdd"		: iops_hdd,
				"latency_ssd"	: latency_ssd,
				"iops_ssd"		: iops_ssd }

if __name__ == "__main__":
	try:
		conn = psycopg2.connect(database='tiramisu', user='postgres', host='localhost', port='5432', password='12344321')
	except:
		print "Nooooooooo"

	c = conn.cursor()

	arg 		= sys.argv
	name 		= arg[1]

	get_state = get_state(name, c)
	latency_vm 	= get_state["latency_vm"]
	iops_vm 	= get_state["iops_vm"]
	latency_hdd	= get_state["latency_hdd"]
	iops_hdd 	= get_state["iops_hdd"]
	latency_ssd	= get_state["latency_ssd"]
	iops_ssd 	= get_state["iops_ssd"]

	state_iops = { 	"SSD" : iops_ssd,
					"HDD" : iops_hdd }

	state_latency = { 	"SSD" : latency_ssd,
						"HDD" : latency_hdd }

	cost = {	"SSD" = 773.0937,
				"HDD" = 429.49	}

	# set default value to cheap storage
	ans_iops = "HDD"
	ans_latency = "HDD"
	ans = "HDD"

	# line of iops
	for i in sorted(state_iops, key=state_iops.get, reverse=False):
		# sorted min to max
		print i, state_iops[i]
		if iops_vm <= state_iops[i]:
			ans_iops = i
			break

	# line of latency
	for j in sorted(state_latency, key=state_latency.get, reverse=True):
		# sorted max to min
		print j, state_latency[j]
		if latency_vm <= state_latency[j]:
			ans_latency = j
			break

	if ans_latency != ans_iops:
		ans = "HDD"
	else:
		ans = ans_iops

	c.execute("select current_pool from tiramisu_storage where vm_name=%s", (name,))
	pool = c.fetchone()
	current = pool[0]

	if ans != current:
		c.execute("update tiramisu_storage set appropiate_pool=%s where vm_name=%s",(ans,name,))
	
	conn.commit()
	c.close()