import javax.swing.*;
import java.awt.*;
import java.awt.geom.*;
public class SwingDemo {
    public static void main(String[] a) {
        SwingUtilities.invokeLater(() -> {
            JFrame f = new JFrame("XEF Swing demo");
            JPanel p = new JPanel(new BorderLayout());
            p.add(new JPanel() {
                protected void paintComponent(Graphics g0) {
                    super.paintComponent(g0);
                    Graphics2D g = (Graphics2D) g0;
                    g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
                    for (int i = 0; i < 12; i++) {
                        g.setColor(Color.getHSBColor(i / 12f, 0.8f, 0.9f));
                        g.fill(new Ellipse2D.Double(40 + i * 25, 30 + i * 10, 120, 80));
                    }
                    g.setColor(Color.BLACK);
                    g.setFont(new Font("SansSerif", Font.BOLD, 28));
                    g.drawString("Java2D on arm64 via XEF", 40, 260);
                }
            }, BorderLayout.CENTER);
            JPanel south = new JPanel();
            south.add(new JButton("OK")); south.add(new JCheckBox("check", true)); south.add(new JTextField("text field", 12));
            south.add(new JComboBox<>(new String[]{"one", "two"})); south.add(new JSlider(0, 100, 40));
            p.add(south, BorderLayout.SOUTH);
            f.setContentPane(p); f.setSize(700, 400); f.setLocation(100, 100); f.setVisible(true);
        });
    }
}
