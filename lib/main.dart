import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  await Hive.initFlutter();
  await Hive.openBox('user_prefs');
  runApp(const StepRewardApp());
}

class StepRewardApp extends StatelessWidget {
  const StepRewardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Step Reward App',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        fontFamily: 'sans-serif',
      ),
      home: const MainNavigationShell(),
    );
  }
}

// ==========================================
// 1. MAIN NAVIGATION SHELL
// ==========================================
class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    MilestonesScreen(),
    ShopScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: Icon(Icons.home_filled, color: _currentIndex == 0 ? Colors.orange : Colors.grey),
              onPressed: () => setState(() => _currentIndex = 0),
            ),
            IconButton(
              icon: Icon(Icons.local_activity_rounded, color: _currentIndex == 1 ? Colors.orange : Colors.grey),
              onPressed: () => setState(() => _currentIndex = 1),
            ),
            IconButton(
              icon: Icon(Icons.card_giftcard, color: _currentIndex == 2 ? Colors.orange : Colors.grey),
              onPressed: () => setState(() => _currentIndex = 2),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. DASHBOARD SCREEN
// ==========================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Stream<StepCount> _stepCountStream;
  int _steps = 0;
  int _coins = 0;
  int _dailyGoal = 10000;
  bool _rewardClaimed = false;
  final box = Hive.box('user_prefs');

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    initPedometer();
  }

  void _loadLocalData() {
    setState(() {
      _coins = box.get('coins', defaultValue: 0);
      _rewardClaimed = box.get('rewardClaimed', defaultValue: false);
      _dailyGoal = box.get('dailyGoal', defaultValue: 10000);
      // Load last calculated steps instantly on startup to avoid showing "0"
      _steps = box.get('lastSteps', defaultValue: 0);
    });
  }

  Future<void> initPedometer() async {
    var status = await Permission.activityRecognition.request();
    if (status.isGranted) {
      _stepCountStream = Pedometer.stepCountStream;
      _stepCountStream.listen(onStepCount).onError(onStepError);
    }
  }

  void onStepCount(StepCount event) {
    int totalDeviceSteps = event.steps;
    String todayKey = DateTime.now().toIso8601String().substring(0, 10);
    String savedDate = box.get('savedDate', defaultValue: todayKey);

    if (savedDate != todayKey) {
      box.put('savedDate', todayKey);
      box.put('baselineSteps', totalDeviceSteps);
      box.put('rewardClaimed', false);
      setState(() => _rewardClaimed = false);
    }

    if (!box.containsKey('baselineSteps')) {
      box.put('baselineSteps', totalDeviceSteps);
    }

    int baselineSteps = box.get('baselineSteps', defaultValue: totalDeviceSteps);
    int calculatedSteps = totalDeviceSteps - baselineSteps;
    if (calculatedSteps < 0) {
      box.put('baselineSteps', 0);
      calculatedSteps = totalDeviceSteps;
    }

    // Save latest steps so it loads instantly next time
    box.put('lastSteps', calculatedSteps);

    setState(() {
      _steps = calculatedSteps;
    });
  }

  void onStepError(error) {
    // Keep last known steps on error instead of resetting to 0
  }

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
    _loadLocalData();
  }

  void _claimReward() {
    if (_rewardClaimed) return;
    setState(() {
      _coins += 50;
      _rewardClaimed = true;
    });
    box.put('coins', _coins);
    box.put('rewardClaimed', _rewardClaimed);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🎉 Successfully claimed 50 StepCoins!')),
    );
  }

  void _showGoalDialog() {
    TextEditingController controller = TextEditingController(text: _dailyGoal.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Daily Step Goal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Enter step goal e.g. 8000'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              int newGoal = int.tryParse(controller.text) ?? 10000;
              setState(() {
                _dailyGoal = newGoal;
              });
              box.put('dailyGoal', newGoal);
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String distanceKm = (_steps * 0.0007).toStringAsFixed(1);
    int calories = (_steps * 0.04).toInt();
    double goalProgress = (_steps / _dailyGoal).clamp(0.0, 1.0);

    return SafeArea(
      child: RefreshIndicator(
        color: Colors.orange,
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Hey Buddy!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                      const SizedBox(height: 4),
                      Text('Goal: $_dailyGoal steps/day', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, color: Colors.orange),
                        onPressed: _showGoalDialog,
                        tooltip: 'Edit Goal',
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.monetization_on, color: Colors.orange, size: 20),
                            const SizedBox(width: 6),
                            Text('$_coins', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Bento Grid Cards
              Row(
                children: [
                  // Activity Card
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(steps: _steps, dailyGoal: _dailyGoal))),
                      child: Container(
                        height: 160,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text('Activity', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                                Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$_steps steps', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: goalProgress,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Distance & Calories Column
                  Expanded(
                    child: Column(
                      children: [
                        // Distance Card
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DistanceDetailScreen(distanceKm: distanceKm, steps: _steps))),
                          child: Container(
                            height: 72,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text('Distance', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text('$distanceKm km', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Calories Card
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaloriesDetailScreen(calories: calories))),
                          child: Container(
                            height: 72,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text('Calories', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text('$calories kcal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Milestone Reward Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Milestone Reward', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(_rewardClaimed ? 'Claimed! 🎉' : 'Claim 50 StepCoins', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _rewardClaimed ? Colors.grey : Colors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _rewardClaimed ? null : _claimReward,
                      child: Text(_rewardClaimed ? 'Done' : 'Claim', style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 3. DETAILED SUB-SCREENS
// ==========================================
class ActivityDetailScreen extends StatelessWidget {
  final int steps;
  final int dailyGoal;
  const ActivityDetailScreen({super.key, required this.steps, required this.dailyGoal});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> weeklyData = [
      {'day': 'Mon', 'steps': 10600},
      {'day': 'Tue', 'steps': 5400},
      {'day': 'Wed', 'steps': 7200},
      {'day': 'Thu', 'steps': 10500},
      {'day': 'Fri', 'steps': 3400},
      {'day': 'Sat', 'steps': 8300},
      {'day': 'Sun', 'steps': steps},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Goal & Activity', style: TextStyle(color: Colors.black87)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Goal: $dailyGoal steps', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text('$steps steps today', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              height: 260,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: weeklyData.map((data) {
                  double barHeight = (data['steps'] / (dailyGoal > 12000 ? dailyGoal : 12000)) * 150;
                  if (barHeight > 150) barHeight = 150;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${(data['steps'] / 1000).toStringAsFixed(1)}k', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Container(
                        width: 24,
                        height: barHeight < 10 ? 10 : barHeight,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(data['day'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DistanceDetailScreen extends StatelessWidget {
  final String distanceKm;
  final int steps;
  const DistanceDetailScreen({super.key, required this.distanceKm, required this.steps});

  @override
  Widget build(BuildContext context) {
    // Estimate walking time: average 100 steps per minute
    int totalMinutes = (steps / 100).round();
    int hours = totalMinutes ~/ 60;
    int minutes = totalMinutes % 60;
    String timeString = hours > 0 ? '$hours hrs $minutes mins' : '$minutes mins';

    return Scaffold(
      appBar: AppBar(title: const Text('Distance Details'), backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.black87)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.map, size: 80, color: Colors.orange),
              const SizedBox(height: 16),
              Text('$distanceKm km', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Total distance covered today.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.timer, color: Colors.orange),
                    const SizedBox(width: 10),
                    Text('Active Walk Time: $timeString', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CaloriesDetailScreen extends StatelessWidget {
  final int calories;
  const CaloriesDetailScreen({super.key, required this.calories});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calorie Breakdown'), backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.black87)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_fire_department, size: 80, color: Colors.deepOrange),
            const SizedBox(height: 16),
            Text('$calories kcal', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Estimated active energy burned through movement.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 4. MILESTONES SCREEN
// ==========================================
class MilestonesScreen extends StatelessWidget {
  const MilestonesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Milestones & Streaks', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: const [
                  MilestoneTile(title: 'First 1,000 Steps', subtitle: 'Completed', isDone: true),
                  MilestoneTile(title: '5,000 Steps Daily Goal', subtitle: 'In Progress', isDone: false),
                  MilestoneTile(title: '10,000 Step Elite Club', subtitle: 'Locked', isDone: false),
                  MilestoneTile(title: '7-Day Streak Warrior', subtitle: 'Locked', isDone: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MilestoneTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isDone;

  const MilestoneTile({super.key, required this.title, required this.subtitle, required this.isDone});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDone ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(isDone ? Icons.check : Icons.lock, color: isDone ? Colors.orange : Colors.grey),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 5. SHOP SCREEN
// ==========================================
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('StepShop', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Spend your earned StepCoins on custom themes and rewards!', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: const [
                  ShopItemCard(title: 'Neon Dark Theme', cost: '100 Coins', icon: Icons.dark_mode),
                  ShopItemCard(title: 'Gold Crown Avatar', cost: '250 Coins', icon: Icons.military_tech),
                  ShopItemCard(title: 'Coffee Discount', cost: '500 Coins', icon: Icons.coffee),
                  ShopItemCard(title: 'Mystery Box', cost: '50 Coins', icon: Icons.card_giftcard),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShopItemCard extends StatelessWidget {
  final String title;
  final String cost;
  final IconData icon;

  const ShopItemCard({super.key, required this.title, required this.cost, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Colors.orange),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          Text(cost, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}